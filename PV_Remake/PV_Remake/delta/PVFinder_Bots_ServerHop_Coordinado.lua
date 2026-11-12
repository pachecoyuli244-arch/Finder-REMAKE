
-- PVFINDER V3 | AUTO NODE | SIN PANEL
-- Registro automatico, sin keys manuales
-- Solo lectura de datos replicados en el cliente

local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local AREAS = {
    cherryblossom = "Cherry Blossom",
    lightdark = "Light Dark",
    angelsdemons = "Light Dark",
    titantemple = "Titan Temple",
    enchantedforest = "Enchanted Forest",
    -- Update 12: nuevos huevos del bioma Alien sin lista fija de mascotas.
    alien = "Alien",
    alienbiome = "Alien",
    alienworld = "Alien",
    alienlagoon = "Alien Lagoon"
}

-- BOT AUTO-HOP: catálogo de PVFINDER y Alien desde Secreto.
-- El scanner V3 independiente permanece sin cambios.

local function allRarity(asset)
    local r = type(asset) == "table" and asset.Rarity or nil
    if type(r) == "table" then
        return tostring(r.DisplayName or r._id or "Desconocida")
    elseif type(r) == "string" then
        return r
    end
    return "Desconocida"
end

local function norm(x)
    return tostring(x or ""):lower():gsub("[^%w]", "")
end

-- Reconoce variantes del ID de la zona Alien publicadas por el juego.
-- Los nombres y rarezas de nuevas mascotas siguen leyendose de Assets.Directory.
local function resolveZone(areaId)
    local key = norm(areaId)
    if AREAS[key] then return AREAS[key] end
    if key:find("alien", 1, true) then return "Alien" end
    return nil
end

local function module(path)
    local node = RS
    for _, part in ipairs(path) do
        node = node:FindFirstChild(part)
        if not node then return nil end
    end
    if not node:IsA("ModuleScript") then return nil end
    local ok, value = pcall(require, node)
    return ok and value or nil
end

local EggState = module({"Client", "EggState"})
local Assets = module({"Data", "Assets"})
local Mutations = module({"Shared", "Modules", "Mutations"})
local EggRecords = module({"Shared", "Util", "EggRecords"})
local HalloweenPets = module({"Data", "HalloweenPets"})

local DIR = type(Assets) == "table"
    and type(Assets.Directory) == "table"
    and Assets.Directory or {}

local SPECS = type(HalloweenPets) == "table"
    and type(HalloweenPets.Specs) == "table"
    and HalloweenPets.Specs or {}

-- CATALOGO V3

local index = {}

local function addAlias(name, asset, id)
    local k = norm(name)
    if k == "" or type(asset) ~= "table" then return end

    local old = index[k]
    if old == nil then
        index[k] = {
            asset = asset,
            id = tostring(id)
        }
    elseif old ~= false and old.id ~= tostring(id) then
        index[k] = false
    end
end

for id, data in pairs(DIR) do
    if type(data) == "table" then
        addAlias(id, data, id)
        addAlias(data.DisplayName, data, id)
    end
end

for key, spec in pairs(SPECS) do
    if type(spec) == "table" then
        local id = tostring(spec.Id or key)
        local data = DIR[id] or DIR[key]

        if type(data) == "table" then
            addAlias(id, data, id)
            addAlias(key, data, id)
            addAlias(spec.EggSource, data, id)
            addAlias(spec.EggModel, data, id)
        end
    end
end

local function findAsset(source)
    local k = norm(source)

    if k == "" or k == "halloweenegg" then
        return nil
    end

    local match = index[k]

    if type(match) == "table" then
        return match.asset, match.id
    end

    local direct = DIR[tostring(source)]

    if type(direct) == "table" then
        return direct, tostring(source)
    end

    return nil
end

local function rarity(asset)
    return allRarity(asset)
end

local function scaleFactor(scale)
    if scale > 5 then
        return (scale / 5)^1.2 * 19.637875755794113
    end

    return scale^1.85
end

local function earnings(asset, scale, muts)
    local base = type(asset) == "table"
        and tonumber(asset.EarningRate) or nil

    if not base then return nil end

    local mult = 1

    if type(muts) == "table"
        and type(Mutations) == "table"
        and type(Mutations.EarningsFor) == "function" then

        local ok, value = pcall(Mutations.EarningsFor, muts)

        if ok and type(value) == "number" and value > 0 then
            mult = value
        end
    end

    return base * scaleFactor(scale) * mult
end

local function weight(id, scale)
    if type(EggRecords) == "table"
        and type(EggRecords.WeightKgForScale) == "function" then

        local ok, n = pcall(
            EggRecords.WeightKgForScale,
            id,
            scale
        )

        if ok then
            return tonumber(n)
        end
    end

    return nil
end

local function mutationNames(muts)
    if type(muts) ~= "table" then
        return "Sin datos"
    end

    local a = {}

    for k, v in pairs(muts) do
        if v == true then
            table.insert(a, tostring(k))
        elseif type(v) == "string" then
            table.insert(a, v)
        end
    end

    table.sort(a)

    return #a == 0 and "Ninguna"
        or table.concat(a, ", ")
end

local function getScale(model)
    if model:IsA("Model") then
        local ok, n = pcall(function()
            return model:GetScale()
        end)

        if ok and type(n) == "number" then
            return n
        end
    end

    return nil
end

local function halloweenZone(obj)
    local attr = obj:GetAttribute("Zone")

    if attr ~= nil then
        return tostring(attr)
    end

    local dimension = workspace:FindFirstChild("HalloweenDimension")
    local zones = dimension and dimension:FindFirstChild("Zones")

    if zones then
        local ok, pos = pcall(function()
            return obj:IsA("Model")
                and obj:GetPivot().Position or obj.Position
        end)

        if ok and typeof(pos) == "Vector3" then
            for i = 3, 1, -1 do
                local part = zones:FindFirstChild("Zone" .. i)

                if part and part:IsA("BasePart") then
                    local p = part.CFrame:PointToObjectSpace(pos)

                    if math.abs(p.X) <= part.Size.X / 2
                        and math.abs(p.Z) <= part.Size.Z / 2 then
                        return tostring(i)
                    end
                end
            end
        end
    end

    return "?"
end

-- LECTURA DE HUEVOS PARA BOT AUTO-HOP

local knownNames = {}
-- Cuando Halloween no expone UID, crear ID estable durante esta sesion.
-- No utilizar el indice de GetChildren, porque cambia al aparecer/desaparecer.
local localEggIDs = setmetatable({}, {__mode = "k"})

local RADAR_CATALOG={
    ["gorilla king"]=true,
    ["nightflame"]=true,
    ["cosmic dragon"]=true,
    ["cosmic skeleton boss"]=true,
    ["gorillastein"]=true,
    ["abomination kong"]=true,
    ["alien skeleton boss"]=true,
    ["archangel"]=true,
    ["cave dragon"]=true,
    ["celestial sunlion"]=true,
    ["centaur"]=true,
    ["eternal lunar dragon"]=true,
    ["gargoyle"]=true,
    ["godzilla"]=true,
    ["jellyfish"]=true,
    ["king kong"]=true,
    ["kitsune"]=true,
    ["medusa"]=true,
    ["mosasaurus"]=true,
    ["oni tiger"]=true,
    ["pegasus"]=true,
    ["pure jellyfish"]=true,
    ["razorfang"]=true,
    ["royal skywhale"]=true,
    ["shark"]=true,
    ["shelltide voyager"]=true,
    ["skeleton horse"]=true,
    ["stag"]=true,
    ["starry fox"]=true,
    ["unicorn"]=true,
    ["voidseer pumpkin"]=true,
    ["werewolf"]=true,
    ["world burner"]=true,
}

local function catalogKey(value)
    return tostring(value or ""):match("^%s*(.-)%s*$"):lower()
end

local ALIEN_RADAR_RARITIES={secret=true,eternal=true,divine=true}
local function catalogIncludes(name, zone, asset)
    local area=catalogKey(zone)
    if area=="alien" or area=="alien zone" or area=="zona alien" then
        return ALIEN_RADAR_RARITIES[catalogKey(rarity(asset))]==true
    end
    return RADAR_CATALOG[catalogKey(name)]==true
end

local function collect()
    local rows = {}
    local seen = {}
    local scopes = {}
    local present = {}

    -- REGISTRO GLOBAL

    if type(EggState) == "table"
        and type(EggState.ReadFieldEggs) == "function" then

        local ok, snap = pcall(EggState.ReadFieldEggs)

        if ok and type(snap) == "table"
            and type(snap.Records) == "table" then

            table.insert(scopes, "G")
            for key, rec in pairs(snap.Records) do
                if type(rec) == "table" then
                    local zone = resolveZone(rec.AreaId)
                    local state = tostring(rec.State or "?")
                    local uid = tostring(rec.Uid or key)
                    if state == "Slot" or state == "Dropped" then present["G/" .. uid] = true end

                    if zone
                        and (state == "Slot" or state == "Dropped")
                        and not seen["G/" .. uid] then

                        seen["G/" .. uid] = true

                        local asset, id = findAsset(rec.AssetCategory)
                        local rawName = asset and (asset.DisplayName or id) or rec.AssetCategory
                        local displayName = tostring(rawName or "Huevo no identificado")
                        if displayName == "" then displayName = "Huevo no identificado" end
                        if catalogIncludes(displayName,zone,asset) then
                            local reportedScale = tonumber(rec.AssetScale)
                            local scale = reportedScale or 1
                            local muts = type(rec.Mutations) == "table" and rec.Mutations or {}
                            table.insert(rows, {
                                name = displayName,
                                rarity = rarity(asset),
                                zone = zone,
                                uid = uid,
                                status = state,
                                cash = asset and earnings(asset, scale, muts) or nil,
                                kg = asset and weight(id, scale) or nil,
                                scale = scale,
                                multiplier = reportedScale,
                                muts = mutationNames(muts),
                                source = "GLOBAL"
                            })
                        end
                    end
                end
            end
        end
    end

    -- HALLOWEEN

    local dim = workspace:FindFirstChild("HalloweenDimension")
    local eggs = dim and dim:FindFirstChild("WorldEggs")

    if eggs then
        table.insert(scopes, "H")
        for idx, obj in ipairs(eggs:GetChildren()) do
            local rawUid = obj:GetAttribute("HalloweenEggUid")
            if not rawUid then
                if not localEggIDs[obj] then
                    localEggIDs[obj] = "local-" .. HttpService:GenerateGUID(false)
                end
                rawUid = localEggIDs[obj]
            end
            local uid = tostring(rawUid)
            present["H/" .. uid] = true

            local source = obj:GetAttribute("PreparedSourceName")

            if source and tostring(source) ~= "" then
                knownNames[uid] = tostring(source)
            else
                source = knownNames[uid]
            end

            if source and norm(source) ~= "halloweenegg" then
                local asset = findAsset(source)
                local displayName = tostring((asset and asset.DisplayName) or source)

                if catalogIncludes(displayName) and not seen["H/" .. uid] then
                    seen["H/" .. uid] = true
                    local scale = getScale(obj)

                    table.insert(rows, {
                        name = displayName,
                        rarity = rarity(asset),
                        zone = "Halloween Z" .. halloweenZone(obj),
                        uid = uid,
                        status = "WorldEgg",
                        cash = asset and earnings(asset, scale or 1, nil) or nil,
                        kg = nil,
                        scale = scale or 1,
                        multiplier = scale,
                        muts = "No expuestas",
                        source = "HALLOWEEN"
                    })
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if (a.cash or -1) == (b.cash or -1) then
            return a.uid < b.uid
        end

        return (a.cash or -1) > (b.cash or -1)
    end)

    return rows, scopes, present
end

-- PVFINDER BOT HOP | Catálogo del radar, snapshot, salto coordinado
-- Las mismas fuentes/ingresos de V3, sin panel.
-- REQUIERE /api/hop/start, /api/hop/next y /api/hop/snapshot.
local BASE = "https://pvfinder.onrender.com"
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer
if not player then warn("[PVFINDER] No hay LocalPlayer");return end

local ENV = (type(getgenv)=="function" and getgenv()) or _G
if type(ENV.PVF_AUTO_NODE_STOP)=="function" then pcall(ENV.PVF_AUTO_NODE_STOP) end
if type(ENV.PVFINDER_V3_FEED_STOP)=="function" then pcall(ENV.PVFINDER_V3_FEED_STOP) end
if type(ENV.PVF_HOP_STOP)=="function" then pcall(ENV.PVF_HOP_STOP) end
local running=true

-- MODO LIGERO PARA BOTS: solo presentacion local, sin alterar datos del juego.
-- No elimina instancias ni modifica el escaner V3.
local RunService=game:GetService("RunService")
local renderOff=false
local qualityReduced=false
if ENV.PVF_HOP_LIGHT_MODE~=false then
    qualityReduced=pcall(function()
        settings().Rendering.QualityLevel=Enum.QualityLevel.Level01
    end)
    renderOff=pcall(function()
        RunService:Set3dRenderingEnabled(false)
    end)
end
ENV.PVF_HOP_STOP=function()
    running=false
    if renderOff then
        pcall(function() RunService:Set3dRenderingEnabled(true) end)
    end
end
local PLACE=tonumber(game.PlaceId)
local JOB=tostring(game.JobId or "")
local AUTH_FILE="PVFinder_Hop_Auth_"..tostring(player.UserId)..".txt"
local session=""
local retryDelay=3
local assignedJob=nil
local function status(message)
    ENV.PVF_HOP_STATUS=tostring(message)
    print("[PVFINDER HOP] "..tostring(message))
end
local function requestFunction()
    if type(request)=="function" then return request end
    if type(http_request)=="function" then return http_request end
    if type(syn)=="table" and type(syn.request)=="function" then return syn.request end
    if type(http)=="table" and type(http.request)=="function" then return http.request end
    return nil
end
local REQUEST=requestFunction()
if not REQUEST then status("SIN HTTP DELTA; no se puede coordinar ni enviar");return end
local function http(method,url,data,auth)
    local headers={["Accept"]="application/json"}
    local opt={Url=url,Method=method,Headers=headers,Timeout=20}
    if data~=nil then
        headers["Content-Type"]="application/json"
        opt.Body=HttpService:JSONEncode(data)
    end
    if auth and auth~="" then headers.Authorization="Bearer "..auth end
    local ok,res=pcall(REQUEST,opt)
    if not ok or type(res)~="table" then return 0,nil end
    local code=tonumber(res.StatusCode or res.Status or res.status_code) or 0
    local parsedOk,parsed=pcall(function()return HttpService:JSONDecode(tostring(res.Body or "{}"))end)
    return code,parsedOk and type(parsed)=="table" and parsed or nil
end
local function api(path,data)
    return http("POST",BASE..path,data,session)
end
local activityPhase,activityReason,lastActivityAt
local activityPending,activitySending
local function activity(phase,reason)
    local now=os.time()
    if phase==activityPhase and reason==activityReason and now-(lastActivityAt or 0)<30 then return end
    if session=="" then return end
    activityPhase,activityReason,lastActivityAt=phase,reason,now
    activityPending={phase=phase,reason=reason}
    if activitySending then return end
    activitySending=true
    task.spawn(function()
        while activityPending and running do
            local pending=activityPending
            activityPending=nil
            pcall(api,"/api/collector/activity",pending)
        end
        activitySending=false
    end)
end
local function loadSession()
    if type(ENV.PVF_HOP_TOKEN)=="string" then session=ENV.PVF_HOP_TOKEN end
    if session=="" and type(readfile)=="function" then
        local ok,value=pcall(readfile,AUTH_FILE)
        if ok and type(value)=="string" then session=value end
    end
    if type(session)~="string" or not session:match("^pvfa_[%w_%-]+$") then session="" end
end
local function saveSession(token)
    session=token
    ENV.PVF_HOP_TOKEN=token
    if type(writefile)=="function" then pcall(writefile,AUTH_FILE,token) end
end
local function enroll()
    if session~="" then return true end
    local code,res=http("POST",BASE.."/api/collector/register",{place_id=PLACE,server_id=JOB},nil)
    if code==201 and res and res.ok and type(res.session_token)=="string" then
        saveSession(res.session_token)
        status("Nodo registrado | "..tostring(res.label or "PVFINDER"))
        return true
    end
    status("REGISTRO HTTP "..tostring(code).." | verifica registro automatico en Render")
    return false
end
local function ensureStart()
    for attempt=1,3 do
        if not running then return nil end
        if enroll() then
            local code,res=api("/api/hop/start",{place_id=PLACE,server_id=JOB})
            if code==200 and res and res.ok then
                return res.scan==true
            end
            if code==401 then
                status("Sesion caducada; renovando")
                saveSession("")
            else
                status("RESERVA ACTUAL HTTP "..tostring(code))
            end
        end
        task.wait(math.min(2*attempt,6))
    end
    return nil
end
local function money(n)
    n=tonumber(n)
    if not n then return "N/D" end
    if n>=1e12 then return string.format("$%.2fT/s",n/1e12) end
    if n>=1e9 then return string.format("$%.2fB/s",n/1e9) end
    if n>=1e6 then return string.format("$%.2fM/s",n/1e6) end
    return string.format("$%.0f/s",n)
end
local function pack(rows,scopes)
    local items={}
    for _,r in ipairs(rows) do
        local cash=tonumber(r.cash)
        -- Evita rechazar todo el lote por valores imposibles.
        if cash and (cash<0 or cash~=cash or cash==math.huge or cash>=1e18) then cash=nil end
        local kg=tonumber(r.kg)
        if kg and (kg<0 or kg~=kg or kg==math.huge or kg>=1e18) then kg=nil end
        local multiplier=tonumber(r.multiplier)
        if multiplier and (multiplier<=0 or multiplier~=multiplier or multiplier>=1e18) then multiplier=nil end
        items[#items+1]={
            place_id=PLACE, server_id=JOB,
            egg_id=(r.source=="HALLOWEEN" and "H/" or "G/")..tostring(r.uid),
            egg_name=tostring(r.name),rarity=r.rarity,biome=r.zone,
            income_per_second=cash,
            income_type=cash and "ESTIMADO" or "DESCONOCIDO",
            weight_kg=kg, multiplier=multiplier,
            mutation=(r.muts=="Sin datos" or r.muts=="No expuestas") and nil or r.muts
        }
    end
    return {place_id=PLACE,server_id=JOB,items=items,scopes=(#rows<=500) and scopes or {}}
end
local function recheckPresence(payload, snapshotAt)
    if #payload.items==0 or type(snapshotAt)~="number" then return end
    local candidates={}
    for _,egg in ipairs(payload.items) do
        candidates[#candidates+1]=egg.egg_id
    end
    -- Observar dos veces el mismo servidor; una fuente que no se pudo leer
    -- nunca cuenta como ausencia.
    for _,delay in ipairs({4,1.5}) do
        task.wait(delay)
        if not running then return end
        local ok,_,scopes,present=pcall(collect)
        if not ok or type(scopes)~="table" or type(present)~="table" then return end
        local available={}
        for _,scope in ipairs(scopes) do available[scope]=true end
        local missing={}
        for _,id in ipairs(candidates) do
            if available[id:sub(1,1)] and not present[id] then
                missing[#missing+1]=id
            end
        end
        if #missing==0 then return end
        candidates=missing
    end
    local code,res=api("/api/hop/recheck",{
        place_id=PLACE,server_id=JOB,snapshot_at=snapshotAt,missing_ids=candidates
    })
    if code==200 and res and (tonumber(res.marked_absent) or 0)>0 then
        status("ROBADOS CONFIRMADOS | "..tostring(res.marked_absent))
    end
end
local function scanAndSend()
    activity("scanning","reading_sources")
    local rows,scopes=nil,nil
    local deadline=os.clock()+16
    while running and os.clock()<deadline do
        local ok,a,b=pcall(collect)
        if ok and type(a)=="table" and type(b)=="table" and #b>0 then
            -- Dejar que terminen de replicarse los datos de las fuentes.
            -- Pequeña pausa para estabilizar replicacion sin esperar 1 s entero.
            task.wait(0.4)
            local ok2,a2,b2=pcall(collect)
            if ok2 and type(a2)=="table" and type(b2)=="table" and #b2>0 then
                rows,scopes=a2,b2
            else rows,scopes=a,b end
            break
        end
        task.wait(0.6)
    end
    if not rows then
        status("SIN FUENTES: no enviamos ni marcamos el servidor; reintentando")
        return false,"sources_unavailable"
    end
    if #rows>500 then
        status("MAS DE 500 DETECCIONES; no enviamos datos truncados")
        return false,"too_many_detections"
    end
    status("ESCANEO "..tostring(#rows).." huevos del catálogo | G/H: "..table.concat(scopes,","))
    local byRarity = {}
    for _,row in ipairs(rows) do
        local rarityName = tostring(row.rarity or "Desconocida")
        byRarity[rarityName] = (byRarity[rarityName] or 0) + 1
    end
    local raritySummary = {}
    for rarityName,count in pairs(byRarity) do
        raritySummary[#raritySummary+1] = rarityName..":"..tostring(count)
    end
    table.sort(raritySummary)
    if #raritySummary>0 then status("RAREZAS | "..table.concat(raritySummary," | ")) end
    if #rows>0 then status("TOP: "..tostring(rows[1].name).." "..money(rows[1].cash)) end
    activity("scanning","sending_snapshot")
    local payload=pack(rows,scopes)
    for attempt=1,4 do
        if not running then return false end
        local code,res=api("/api/hop/snapshot",payload)
        if code==200 and res and res.ok then
            status("SNAPSHOT OK | "..tostring(res.accepted or #rows).." huevos | JobId "..JOB)
            recheckPresence(payload,res.snapshot_at)
            return true
        elseif code==409 then
            status("JOBID ya reportado u ocupado; evitando duplicacion")
            return true
        elseif code==401 then
            status("AUTH 401; renovando y validando reserva")
            saveSession("")
            local scan=ensureStart()
            if scan==false then return true end
            if scan==nil then return false end
        else
            local reason=(res and tostring(res.error or res.message or "")) or ""
            reason=reason:sub(1,160)
            status("ENVIO HTTP "..tostring(code).." | "..reason.." | intento "..attempt)
            -- Un error de validacion no se arregla repitiendo el mismo lote.
            if code==400 or code==403 then return false,"snapshot_rejected" end
        end
        task.wait(attempt*2)
    end
    return false,"snapshot_error"
end
-- Mantener la sesion de recolector activa durante horas de espera entre saltos.
-- Se renueva antes de buscar cada siguiente JobId.
local lastRenewedAt=0
local function ensureSessionFresh()
    if not enroll() then return false end
    if lastRenewedAt>0 and time()-lastRenewedAt<10*60 then return true end
    local code,res=api("/api/collector/renew",{})
    if code==200 and res and res.ok then
        lastRenewedAt=time()
        return true
    end
    if code==401 then
        status("Sesion del bot vencida; re-registrando")
        saveSession("")
        if enroll() then
            lastRenewedAt=time()
            return true
        end
    end
    status("No se pudo renovar sesion HTTP "..tostring(code).."; permaneciendo")
    return false
end

local function serverPage(cursor)
    local url="https://games.roblox.com/v1/games/"..tostring(PLACE).."/servers/Public?sortOrder=Asc&limit=100"
    if cursor and cursor~="" then
        -- Las cursors suelen ser URL-safe pero se escapan por precaucion.
        local s=tostring(cursor):gsub("([^%w%-_%.~])",function(c)return string.format("%%%02X",string.byte(c)) end)
        url=url.."&cursor="..s
    end
    local code,data=http("GET",url,nil,nil)
    if code~=200 or not data or type(data.data)~="table" then
        return nil,nil,code
    end
    local candidates={}
    for _,item in ipairs(data.data) do
        local id=type(item)=="table" and item.id or nil
        local playing=type(item)=="table" and tonumber(item.playing) or nil
        local maxPlayers=type(item)=="table" and tonumber(item.maxPlayers) or nil
        -- Admitir todos los servidores publicos con cupo (0, 1, 2, 3+).
        -- Solo se usa lo que la API oficial de Roblox informa como disponible.
        if type(id)=="string" and id~=JOB and playing and maxPlayers
            and playing>=0 and playing%1==0 and maxPlayers>0
            and maxPlayers%1==0 and playing<maxPlayers then
            candidates[#candidates+1]={id=id,playing=playing,maxPlayers=maxPlayers}
        end
    end
    return candidates,data.nextPageCursor,code
end
-- Persistir el recorrido para no hacer un hop en cadena al auto-ejecutar
-- el mismo script despues de llegar a un servidor nuevo.
local HOP_STATE_FILE="PVFinder_Hop_Cadence_"..tostring(player.UserId)..".json"
local hopState={}
local function readHopState()
    if type(readfile)=="function" then
        local ok,raw=pcall(readfile,HOP_STATE_FILE)
        if ok and type(raw)=="string" then
            local parsedOk,record=pcall(function()return HttpService:JSONDecode(raw) end)
            if parsedOk and type(record)=="table" then return record end
        end
    end
    return type(ENV.PVF_HOP_CADENCE)=="table" and ENV.PVF_HOP_CADENCE or {}
end
local function storeHopState()
    ENV.PVF_HOP_CADENCE=hopState
    if type(writefile)=="function" then
        pcall(writefile,HOP_STATE_FILE,HttpService:JSONEncode(hopState))
    end
end
local function forgetPending(job)
    if hopState.pending_to==job then
        hopState.pending_to=nil
        hopState.leaving_job=nil
        storeHopState()
    end
end
local function teleportTo(job)
    activity("moving","teleport_requested")
    assignedJob=job
    -- Solo queda marcado como completado cuando efectivamente llega a otro JobId.
    hopState.pending_to=job
    hopState.leaving_job=JOB
    storeHopState()
    -- Pedir a Delta que vuelva a ejecutar el bot al entrar al nuevo JobId.
    local queue=(type(queue_on_teleport)=="function" and queue_on_teleport)
        or (type(syn)=="table" and type(syn.queue_on_teleport)=="function" and syn.queue_on_teleport)
    if queue then
        local okQueue=pcall(queue,[=[
local environment = getgenv and getgenv() or _G
environment.PVF_HOP_AFTER_TELEPORT = true
local loaderUrl = "https://pvfinder.onrender.com/bot-hop.lua"
-- Render can be briefly unavailable during a deployment.
-- Retry only the script download. Keep the Roblox hop cadence unchanged.
for attempt = 1, 6 do
    local ok, source = pcall(function() return game:HttpGet(loaderUrl) end)
    if ok and type(source) == "string" then
        local chunk = loadstring(source)
        if chunk then
            chunk()
            return
        end
    end
    if attempt < 6 then
        task.wait(math.min(5 * attempt, 20) + math.random(2, 6))
    end
end
warn("[PVFinder] Could not download the scanner after 6 attempts")
]=])
        if not okQueue then
            activity("paused","no_auto_resume")
            status("No se pudo preparar el auto-inicio tras teleport")
        end
    else
        activity("paused","no_auto_resume")
        status("Delta no ofrece queue_on_teleport: activa Auto Execute para continuar tras el salto")
    end
    local failed=false
    local flooded=false
    local conn
    conn=TeleportService.TeleportInitFailed:Connect(function(plr,result,err)
        if plr==player then
            flooded=result==Enum.TeleportResult.Flooded
            failed=true
            status("JOIN FALLIDO "..tostring(result).." | "..tostring(err))
            api("/api/hop/release",{place_id=PLACE,server_id=job,failed=not flooded})
            forgetPending(job)
            assignedJob=nil
        end
    end)
    -- Solo entrada a instancia especifica: no teletransportar a servidor aleatorio.
    local ok,err=pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE,job,player)
    end)
    if not ok then
        local reason=tostring(err):lower()
        flooded=flooded or reason:find("flood",1,true)~=nil or reason:find("too many",1,true)~=nil
        status("TELEPORT NO DISPONIBLE: "..tostring(err))
        if not failed then
            api("/api/hop/release",{place_id=PLACE,server_id=job,failed=not flooded})
            forgetPending(job)
        end
        if conn then conn:Disconnect() end
        assignedJob=nil
        return false,flooded and "roblox_flooded" or nil
    end
    status("TELEPORT solicitado al JobId "..job)
    -- Fallos explícitos pueden pasar al siguiente candidato sin agotar los 8 s.
    local timeout=os.clock()+8
    while running and not failed and game.JobId==JOB and os.clock()<timeout do
        task.wait(0.1)
    end
    if conn then conn:Disconnect() end
    if failed or not running then return false,flooded and "roblox_flooded" or nil end
    if game.JobId==JOB then
        -- Si la instancia no cambia, liberar reserva y continuar buscando.
        api("/api/hop/release",{place_id=PLACE,server_id=job,failed=true})
            forgetPending(job)
        status("Roblox no cambio de servidor; buscando otro")
        assignedJob=nil
        return false
    end
    return true
end
local ROSTER_TTL=60
local HOP_RETRY_SECONDS=60
local function robloxCooldownRemaining()
    local deadline=tonumber(hopState.roblox_retry_at) or 0
    return math.max(0,deadline-os.time())
end

local function staggerRobloxRetry()
    -- Espaciar los reintentos entre bots y conservar la espera si Delta
    -- vuelve a cargar el script.
    local retry=HOP_RETRY_SECONDS+math.random(5,20)
    hopState.roblox_retry_at=os.time()+math.max(retry,robloxCooldownRemaining())
    storeHopState()
    return robloxCooldownRemaining()
end
local prefetchedRoster=nil
local pendingRoster=false

local function cachedRoster()
    local roster=hopState.roster
    if type(roster)~="table" or roster.place~=PLACE or type(roster.choices)~="table"
        or type(roster.at)~="number" or os.time()-roster.at>ROSTER_TTL
        or roster.at>os.time() or #roster.choices==0 then return nil end
    return roster
end

local function nextRosterCursor()
    return hopState.roster_place==PLACE and hopState.roster_next or nil
end

local function fetchRoster(cursor)
    if robloxCooldownRemaining()>0 then return nil,429 end
    local choices,nextCursor,code=serverPage(cursor)
    if code==429 then staggerRobloxRetry() end
    if not choices then return nil,code end
    return {place=PLACE,cursor=cursor,next_cursor=nextCursor,choices=choices,at=os.time()}
end

local function prefetchRoster()
    if cachedRoster() or pendingRoster or robloxCooldownRemaining()>0 then return end
    local cursor=nextRosterCursor()
    pendingRoster=true
    task.spawn(function()
        local ok,roster,code=pcall(fetchRoster,cursor)
        if ok and running then prefetchedRoster={cursor=cursor,roster=roster,code=code,at=os.time()} end
        pendingRoster=false
    end)
end

local function consumeRoster(cursor)
    -- La precarga y la búsqueda comparten la misma consulta.
    local waitingUntil=os.clock()+20
    while pendingRoster and running and os.clock()<waitingUntil do task.wait(0.05) end
    if pendingRoster or not running then return nil,0 end
    local prepared=prefetchedRoster
    prefetchedRoster=nil
    if prepared and prepared.cursor==cursor and os.time()-prepared.at<=ROSTER_TTL then
        return prepared.roster,prepared.code
    end
    return fetchRoster(cursor)
end

local function hop()
    if robloxCooldownRemaining()>0 then return false,"roblox_http_limit" end
    if not ensureSessionFresh() then return false,"session_error" end
    activity("moving","looking_for_server")
    local roster=cachedRoster()
    local cursor=roster and roster.cursor or nextRosterCursor()
    local seen,attempted={},{}
    local eligible=0
    local teleportFailed=false
    local restarted=false
    for page=1,20 do
        if not running then return false end
        if not roster then
            local code
            roster,code=consumeRoster(cursor)
            if not roster and code==400 and cursor and not restarted then
                cursor=nil
                restarted=true
                roster,code=fetchRoster(nil)
            end
            if not roster then
                status("ROBLOX API HTTP "..tostring(code).." en pagina "..page)
                return false,code==429 and "roblox_http_limit" or "roblox_api_error"
            end
        end
        local candidates={}
        for _,entry in ipairs(roster.choices) do
            if type(entry)=="table" and type(entry.id)=="string" and entry.id~=JOB and not seen[entry.id] then
                seen[entry.id]=true
                candidates[#candidates+1]=entry
            end
        end
        eligible=eligible+#candidates
        for _=1,math.min(#candidates,5) do
            if not running then return false end
            local batch={}
            for _,entry in ipairs(candidates) do
                if not attempted[entry.id] then batch[#batch+1]=entry end
            end
            if #batch==0 then break end
            local rc,choice=api("/api/hop/next",{
                place_id=PLACE,current_server=JOB,candidates=batch
            })
            if rc~=200 then
                status("COORDINADOR HTTP "..tostring(rc))
                return false,"coordinator_error"
            end
            local job=choice and choice.server_id
            if type(job)~="string" or job=="" then break end
            attempted[job]=true
            local remaining={}
            for _,entry in ipairs(batch) do
                if entry.id~=job then remaining[#remaining+1]=entry end
            end
            roster.choices=remaining
            hopState.roster=roster
            hopState.roster_place=PLACE
            hopState.roster_next=roster.next_cursor
            -- teleportTo persiste la página restante con la reserva antes de salir.
            status("JOBID NUEVO RESERVADO ("..tostring(choice.player_count or "N/D").." JUGADORES): "..job)
            local moved,reason=teleportTo(job)
            if moved then return true end
            if reason=="roblox_flooded" then return false,reason end
            teleportFailed=true
            task.wait(1)
        end
        cursor=roster.next_cursor
        roster=nil
        hopState.roster=nil
        hopState.roster_place=PLACE
        hopState.roster_next=cursor
        if not cursor or cursor=="" then break end
        task.wait(0.1)
    end
    storeHopState()
    status("Sin JobIds nuevos con cupo (vistos: "..eligible.."); no repetir servidores")
    return false,"no_candidates",teleportFailed and "teleport_failed" or nil
end
if not game:IsLoaded() then game.Loaded:Wait() end
if not PLACE or JOB=="" then status("SIN PLACEID / JOBID");return end

-- Cada bot escanea, espera el ACK de Render y entonces inicia el hop sin retardo fijo.
-- El coordinador reserva JobIds diferentes; nunca se salta si el envio fallo.
-- Los limites de Roblox y reintentos por error siguen aplicando.
hopState=readHopState()
ENV.PVF_HOP_AFTER_TELEPORT=nil
hopState.job=JOB
hopState.entered_at=os.time()
hopState.pending_to=nil
hopState.leaving_job=nil
storeHopState()

status("PVFinder | AUTO HOP TRAS ENVIO | todos los servidores con cupo | JobId "..JOB)
status("MODO LIGERO: render 3D "..(renderOff and "DESACTIVADO" or "NO DISPONIBLE").." | calidad "..(qualityReduced and "BAJA" or "SIN CAMBIOS"))
loadSession()
prefetchRoster()
task.spawn(function()
    local reportFinished=false
    local nextScanAttempt=os.time()
    local nextHopAttempt=nil -- Solo habilitar el hop tras un reporte confirmado o un JobId ya ocupado
    while running do
        -- El escaner y el envio V3 se mantienen intactos.
        if not reportFinished and os.time()>=nextScanAttempt then
            local scan=ensureStart()
            if not running then break end
            if scan==true then
                local delivered,reason=scanAndSend()
                if delivered then
                    reportFinished=true
                    nextHopAttempt=os.time()
                    status("ENVIO CONFIRMADO: hop inmediato a un JobId distinto")
                else
                    activity("paused",reason or "snapshot_error")
                    status("Sin confirmacion del Finder; reintentando, SIN HOP")
                    nextScanAttempt=os.time()+30
                end
            elseif scan==false then
                reportFinished=true
                -- Si el servidor ya pertenece a otro bot, abandonarlo pronto.
                nextHopAttempt=os.time()
                status("JOBID YA VISITADO/OCUPADO: buscando otro sin repetir")
            else
                activity("paused","coordinator_error")
                status("SIN COORDINADOR: reintentando, SIN HOP")
                nextScanAttempt=os.time()+30
            end
        end

        if not running then break end
        if reportFinished and nextHopAttempt and os.time()>=nextHopAttempt then
            status("HOP INMEDIATO: buscando JobId libre y nuevo")
            local hopped,reason,diagnostic=hop()
            if hopped then
                -- No programar otro teleport desde la instancia anterior.
                nextHopAttempt=nil
                running=false
            else
                local retry=reason=="no_candidates" and 12 or HOP_RETRY_SECONDS
                if reason=="roblox_http_limit" then
                    retry=robloxCooldownRemaining()
                    if retry==0 then retry=staggerRobloxRetry() end
                elseif reason=="roblox_flooded" then
                    retry=staggerRobloxRetry()
                end
                nextHopAttempt=os.time()+retry
                activity("paused",diagnostic or reason or "teleport_failed")
                if reason=="roblox_flooded" or reason=="roblox_http_limit" then
                    status("Roblox aplicó un límite; pausa de "..retry.." s")
                else
                    status("Buscando de nuevo en "..retry.." s")
                end
            end
        end
        if activityPhase then activity(activityPhase,activityReason) end
        ENV.PVF_HOP_SECONDS_REMAINING=nextHopAttempt and math.max(0,nextHopAttempt-os.time()) or 0
        task.wait(0.1)
    end
end)
