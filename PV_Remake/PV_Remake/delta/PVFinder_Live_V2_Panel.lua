
-- PVFINDER LIVE V2 | RENDER | PANEL | TODAS LAS RAREZAS
-- Registro automatico, sin keys manuales
-- Solo lectura de datos replicados en el cliente

local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local AREAS = {
    cherryblossom = "Cherry Blossom",
    lightdark = "Light Dark",
    angelsdemons = "Light Dark",
    titantemple = "Titan Temple",
    enchantedforest = "Enchanted Forest"
}

-- Todas las rarezas del catalogo; sin filtro TOP.
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

    return 1
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

-- ESCANER V3 ORIGINAL

local knownNames = {}
-- Cuando Halloween no expone UID, crear ID estable durante esta sesion.
-- No utilizar el indice de GetChildren, porque cambia al aparecer/desaparecer.
local localEggIDs = setmetatable({}, {__mode = "k"})

local function collect()
    local rows = {}
    local seen = {}
    local scopes = {}

    -- REGISTRO GLOBAL

    if type(EggState) == "table"
        and type(EggState.ReadFieldEggs) == "function" then

        local ok, snap = pcall(EggState.ReadFieldEggs)

        if ok and type(snap) == "table"
            and type(snap.Records) == "table" then

            table.insert(scopes, "G")
            for key, rec in pairs(snap.Records) do
                if type(rec) == "table" then
                    local zone = AREAS[norm(rec.AreaId)] or tostring(rec.AreaId or "Desconocido")
                    local state = tostring(rec.State or "?")
                    local uid = tostring(rec.Uid or key)

                    if zone
                        and norm(zone) ~= "prehistoric"
                        and (state == "Slot" or state == "Dropped")
                        and not seen["G/" .. uid] then

                        seen["G/" .. uid] = true

                        local asset, id = findAsset(rec.AssetCategory)
                        local r = rarity(asset)

                        if asset then
                            local scale = tonumber(rec.AssetScale) or 1
                            local muts = type(rec.Mutations) == "table"
                                and rec.Mutations or {}

                            table.insert(rows, {
                                name = tostring(asset.DisplayName or id),
                                rarity = r,
                                zone = zone,
                                uid = uid,
                                status = state,
                                cash = earnings(asset, scale, muts),
                                kg = weight(id, scale),
                                scale = scale,
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

            local source = obj:GetAttribute("PreparedSourceName")

            if source and tostring(source) ~= "" then
                knownNames[uid] = tostring(source)
            else
                source = knownNames[uid]
            end

            if source and norm(source) ~= "halloweenegg" then
                local asset = findAsset(source)
                local r = rarity(asset)

                if asset and not seen["H/" .. uid] then
                    seen["H/" .. uid] = true

                    local scale = getScale(obj)

                    table.insert(rows, {
                        name = tostring(asset.DisplayName or source),
                        rarity = r,
                        zone = "Halloween Z" .. halloweenZone(obj),
                        uid = uid,
                        status = "WorldEgg",
                        cash = earnings(asset, scale, nil),
                        kg = nil,
                        scale = scale,
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

    return rows, scopes
end

-- REGISTRO AUTOMATICO Y LIVE FEED

local TARGETS = {
    { name = "Render", base = "https://pvfinder.onrender.com" }
}

local ENV = (getgenv and getgenv()) or _G

if type(ENV.PVF_AUTO_NODE_STOP) == "function" then
    pcall(ENV.PVF_AUTO_NODE_STOP)
end

if type(ENV.PVFINDER_V3_FEED_STOP) == "function" then
    pcall(ENV.PVFINDER_V3_FEED_STOP)
end

local running = true
ENV.PVF_AUTO_NODE_STATUS = ENV.PVF_AUTO_NODE_STATUS or {}
ENV.PVF_AUTO_NODE_STATUS.Render = "Conectando con Render..."

ENV.PVF_AUTO_NODE_STOP = function()
    running = false
end

local function requestMethod()
    if type(request) == "function" then return request end
    if type(http_request) == "function" then return http_request end

    if type(syn) == "table"
        and type(syn.request) == "function" then
        return syn.request
    end

    if type(http) == "table"
        and type(http.request) == "function" then
        return http.request
    end

    return nil
end

local requestFn = requestMethod()

local function report(target, msg)
    local k = target and target.name or "GENERAL"

    ENV.PVF_AUTO_NODE_STATUS = ENV.PVF_AUTO_NODE_STATUS or {}
    ENV.PVF_AUTO_NODE_STATUS[k] = msg

    print("[PVFINDER AUTO " .. k .. "] " .. msg)
end

if not requestFn then
    report(nil, "HTTP no disponible: escaneo local activo")
end

local function callAPI(target, path, data, sessionToken)
    local headers = {
        ["Content-Type"] = "application/json"
    }

    if sessionToken and sessionToken ~= "" then
        headers.Authorization = "Bearer " .. sessionToken
    end

    local encoded = HttpService:JSONEncode(data or {})

    local ok, res = pcall(requestFn, {
        Url = target.base .. path,
        Method = "POST",
        Timeout = 30,
        Headers = headers,
        Body = encoded
    })

    if not ok or type(res) ~= "table" then
        return 0, nil
    end

    local code = tonumber(
        res.StatusCode or res.Status or res.status_code
    ) or 0

    local rawBody = tostring(res.Body or res.body or "")
    local jsonOK, reply = pcall(function()
        return HttpService:JSONDecode(rawBody)
    end)
    if not jsonOK or type(reply) ~= "table" then
        reply = {error = rawBody ~= "" and rawBody:sub(1, 180) or "Respuesta vacia del servidor"}
    end
    return code, reply
end

local function enroll(target)
    local clock = os.clock()

    if target.retryAt and clock < target.retryAt then
        return false
    end

    local place = tonumber(game.PlaceId)
    local job = tostring(game.JobId or "")

    if not place or place <= 0 or job == "" then
        report(target, "FALTAN PLACEID/JOBID")
        return false
    end

    -- SESION YA REGISTRADA

    if target.token and clock < (target.expiry or 0) - 1800 then
        return true
    end

    -- RENOVACION AUTOMATICA

    if target.token and clock < (target.expiry or 0) then
        local code, reply = callAPI(
            target,
            "/api/collector/renew",
            {},
            target.token
        )

        if code == 200 and reply and reply.ok then
            target.expiry = clock
                + (tonumber(reply.expires_in) or 21600)

            return true
        end

        if code ~= 401 and code ~= 403 then
            report(target, "RENOVACION HTTP " .. tostring(code))
            return true
        end

        target.token = nil
    end

    -- CREACION AUTOMATICA DEL RECOLECTOR

    local code, reply = callAPI(
        target,
        "/api/collector/register",
        {
            place_id = place,
            server_id = job
        },
        nil
    )

    if code == 201
        and reply
        and reply.ok
        and type(reply.session_token) == "string"
        and reply.session_token:match("^pvfa_") then

        target.token = reply.session_token
        target.expiry = clock
            + (tonumber(reply.expires_in) or 21600)

        target.id = reply.collector_id
        target.label = reply.label

        report(target, "REGISTRADO: " .. tostring(target.label))
        return true
    end

    local delay = (code == 429 or code == 403 or code == 404)
        and 300 or 90

    target.retryAt = clock + delay

    if code == 403 then
        report(target, "REGISTRO DESACTIVADO EN SERVIDOR")
    elseif code == 404 then
        report(target, "SERVIDOR SIN ACTUALIZAR (404)")
    else
        report(
            target,
            "NO PUDO REGISTRARSE (HTTP " .. tostring(code) .. ")"
        )
    end

    return false
end

-- PREPARAR HUEVOS PARA EL FEED

local function makePayload(rows)
    local batch = {}

    for i = 1, math.min(#rows, 500) do
        local row = rows[i]
        local income = tonumber(row.cash)

        if income and (
            income < 0
            or income ~= income
            or income == math.huge
        ) then
            income = nil
        end

        local mutation = row.muts

        if mutation == "Sin datos"
            or mutation == "No expuestas" then
            mutation = nil
        end

        batch[#batch + 1] = {
            place_id = tonumber(game.PlaceId),
            server_id = tostring(game.JobId),

            egg_id = (
                row.source == "HALLOWEEN"
                and "H/" or "G/"
            ) .. tostring(row.uid),

            egg_name = tostring(row.name),
            rarity = row.rarity,
            biome = row.zone,

            income_per_second = income,
            income_type = income
                and "ESTIMADO" or "DESCONOCIDO",

            weight_kg = row.kg,
            mutation = mutation
        }
    end

    return {
        place_id = tonumber(game.PlaceId),
        server_id = tostring(game.JobId),
        items = batch
    }
end

-- ENVIAR SNAPSHOTS A LA API LIVE V1
-- En cada snapshot se incluyen todos los huevos reconocidos visibles.
-- Las fuentes que no se pudieron leer NO cuentan para desapariciones.

local busy = false
local lastUpload = -math.huge
local lastStatus = -math.huge

local function upload(rows, scopes)
    if busy or not running or not requestFn then return end
    if os.clock() - lastUpload < 3 then return end

    local payload = makePayload(rows)
    -- Si hay más de 100 huevos, evitamos declarar desapariciones con datos truncados.
    -- Solo declarar desapariciones cuando la lectura de la fuente es completa.
    -- Render admite hasta 500 elementos; si hay mas, no eliminar otros huevos.
    payload.scopes = #rows <= 500 and scopes or {}

    busy = true
    lastUpload = os.clock()

    task.spawn(function()
        for _, target in ipairs(TARGETS) do
            if not running then break end

            if enroll(target) then
                local code, reply = callAPI(
                    target,
                    "/api/collect/snapshot",
                    payload,
                    target.token
                )

                if code == 200 and reply and reply.ok then
                    -- Estado siempre actualizado incluso con cero huevos.
                    ENV.PVF_AUTO_NODE_LAST_OK = os.time()
                    ENV.PVF_AUTO_NODE_STATUS = ENV.PVF_AUTO_NODE_STATUS or {}
                    ENV.PVF_AUTO_NODE_STATUS[target.name] =
                        "ONLINE | " .. tostring(reply.accepted or 0) .. " huevos"
                    if os.clock() - lastStatus >= 30 then
                        lastStatus = os.clock()
                        report(target, "SNAPSHOT OK | "
                            .. tostring(reply.accepted or 0)
                            .. " HUEVOS | "
                            .. tostring(target.label or "Auto Node"))
                    end
                elseif code == 401 then
                    target.token = nil
                    report(target, "SESION VENCIDA; RE-REGISTRO")
                elseif code == 429 then
                    target.retryAt = os.clock() + 120
                    report(target, "LIMITE DE ENVIO (429)")
                else
                    report(target, "SNAPSHOT HTTP " .. tostring(code)
                        .. " | " .. tostring(reply and (reply.error or reply.message) or "Sin detalle"))
                end
            end
        end
        busy = false
    end)
end

-- PANEL MOVIL
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local parent = player:WaitForChild("PlayerGui")
local old = parent:FindFirstChild("PVFinderLiveV2Panel")
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "PVFinderLiveV2Panel"
gui.ResetOnSpawn = false
gui.Parent = parent
local frame = Instance.new("Frame")
frame.Size = UDim2.new(.9,0,.65,0)
frame.Position = UDim2.new(.05,0,.15,0)
frame.BackgroundColor3 = Color3.fromRGB(20,24,35)
frame.Active = true
frame.Draggable = true
frame.Parent = gui
local sizeLimit = Instance.new("UISizeConstraint",frame)
sizeLimit.MaxSize = Vector2.new(500,650)
Instance.new("UICorner",frame).CornerRadius = UDim.new(0,12)
local function makeButton(text,x)
    local b = Instance.new("TextButton")
    b.Text=text
    b.Size=UDim2.new(.46,0,0,42)
    b.Position=UDim2.new(x,0,0,12)
    b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(43,98,185)
    b.Parent=frame
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    return b
end
local scanButton=makeButton("ESCANEAR",.03)
local copyButton=makeButton("COPIAR TODO",.51)
local output=Instance.new("TextBox")
output.Size=UDim2.new(1,-16,1,-72)
output.Position=UDim2.fromOffset(8,62)
output.MultiLine=true
output.ClearTextOnFocus=false
output.TextEditable=true
output.TextWrapped=true
output.TextXAlignment=Enum.TextXAlignment.Left
output.TextYAlignment=Enum.TextYAlignment.Top
output.TextSize=12
output.Font=Enum.Font.Code
output.TextColor3=Color3.fromRGB(230,240,255)
output.BackgroundColor3=Color3.fromRGB(9,13,21)
output.Text="PVFinder iniciando..."
output.Parent=frame
local lastText=""
local function money(n)
    if not n then return "No disponible" end
    local a=math.abs(n)
    if a>=1e12 then return string.format("$%.2fT/s",n/1e12) end
    if a>=1e9 then return string.format("$%.2fB/s",n/1e9) end
    if a>=1e6 then return string.format("$%.2fM/s",n/1e6) end
    if a>=1e3 then return string.format("$%.2fK/s",n/1e3) end
    return string.format("$%.2f/s",n)
end
local previous={}
local function showRows(rows,scopes)
    local current={}
    local added,removed=0,0
    for _,r in ipairs(rows) do
        local id=r.source.."/"..r.uid
        current[id]=true
        if not previous[id] then added=added+1 end
    end
    -- Solo contar desapariciones si ambas fuentes se pudieron leer.
    if #scopes > 0 then
        for id in pairs(previous) do
            local source=id:sub(1,1)
            local valid=false
            for _,v in ipairs(scopes) do
                if v==source then valid=true end
            end
            if valid and not current[id] then removed=removed+1 end
        end
        for id in pairs(previous) do
            local source=id:sub(1,1)
            local valid=false
            for _,v in ipairs(scopes) do
                if v==source then valid=true end
            end
            if not valid then current[id]=true end
        end
        previous=current
    end
    local lines={
        "=== PVFINDER LIVE V2 | TODAS LAS RAREZAS ===",
        "PlaceId: "..tostring(game.PlaceId),
        "JobId: "..tostring(game.JobId),
        "ACTIVOS: "..#rows.." | NUEVOS: "..added.." | DESAPARECIDOS: "..removed,
        "FUENTES LEIDAS: "..table.concat(scopes,", "),
        "ENVIO: "..tostring((ENV.PVF_AUTO_NODE_STATUS or {}).Render or "Pendiente"),
        "-----------------------------------"
    }
    for i,r in ipairs(rows) do
        lines[#lines+1]=string.format("%d. %s | %s | %s",i,r.name,r.rarity,r.zone)
        lines[#lines+1]="Ingreso calculado: "..money(r.cash)
        lines[#lines+1]="Peso: "..(r.kg and string.format("%.2f kg",r.kg) or "N/D").." | Escala: "..tostring(r.scale)
        lines[#lines+1]="Mutacion: "..r.muts.." | Estado: "..r.status
        lines[#lines+1]="Fuente: "..r.source.." | UID: "..r.uid
        lines[#lines+1]=""
    end
    lastText=table.concat(lines,"\n")
    output.Text=lastText
end
local scanBusy=false
local function scanOnce()
    if scanBusy or not running then return end
    scanBusy=true
    local ok,rows,scopes=pcall(collect)
    if ok and type(rows)=="table" and type(scopes)=="table" then
        showRows(rows,scopes)
        ENV.PVF_AUTO_NODE_COUNT=#rows
        ENV.PVF_AUTO_NODE_LAST_SCAN=os.time()
        ENV.PVF_AUTO_NODE_SCOPES=table.concat(scopes,",")
        -- Solo enviar cuando al menos una fuente fue leida.
        if #scopes>0 then upload(rows,scopes) end
    else
        output.Text="ERROR DE LECTURA: "..tostring(rows)
    end
    scanBusy=false
end
scanButton.MouseButton1Click:Connect(function() task.spawn(scanOnce) end)
copyButton.MouseButton1Click:Connect(function()
    if type(setclipboard)=="function" then
        setclipboard(lastText)
    else
        output.Text=lastText
    end
end)
gui.Destroying:Connect(function() running=false end)
report(nil,"PVFINDER LIVE V2 | PANEL | CADA 5 SEGUNDOS")
task.spawn(function()
    while running and gui.Parent do
        scanOnce()
        task.wait(5)
    end
    report(nil,"DETENIDO")
end)
