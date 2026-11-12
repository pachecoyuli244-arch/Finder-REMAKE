-- PVFINDER V4 FULL COLLECTOR: escaneo y envio de todos los huevos TOP visibles.
-- Implementacion independiente de telemetria local. V3 original se conserva.
-- Sin GUI, sin remotos del juego, no cambia ni recoge huevos.
-- Configuracion: env.PVFINDER_COLLECTOR_TOKEN antes de cargar el archivo.
-- No incluir credenciales privadas en este archivo descargable.
-- PVFINDER V3 | SOLO COSMIC / SECRET / ETERNAL / DIVINE
-- Combina Cherry Blossom, Light Dark, Titan Temple, Enchanted Forest y Halloween
-- SOLO LECTURA LOCAL. No recoge huevos ni ejecuta remotos.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local me = Players.LocalPlayer

local AREAS = {
    cherryblossom = "Cherry Blossom",
    lightdark = "Light Dark",
    angelsdemons = "Light Dark",
    titantemple = "Titan Temple",
    enchantedforest = "Enchanted Forest"
}
local ORDER = {"Cherry Blossom", "Light Dark", "Titan Temple", "Enchanted Forest", "Halloween"}
local TOP = {cosmic="Cosmic", secret="Secret", eternal="Eternal", divine="Divine"}
local function norm(x)
    return tostring(x or ""):lower():gsub("[^%w]", "")
end
local function module(path)
    local node = RS
    for _, part in ipairs(path) do
        node = node:FindFirstChild(part)
        if not node then return nil, "Falta " .. table.concat(path, ".") end
    end
    if not node:IsA("ModuleScript") then return nil, "No es modulo" end
    local ok, value = pcall(require, node)
    return ok and value or nil, ok and "OK" or tostring(value)
end
local EggState, eggStatus = module({"Client", "EggState"})
local Assets, assetStatus = module({"Data", "Assets"})
local Mutations = module({"Shared", "Modules", "Mutations"})
local EggRecords = module({"Shared", "Util", "EggRecords"})
local HalloweenPets, halloweenStatus = module({"Data", "HalloweenPets"})
-- Esperar los modulos en conexiones lentas de Android/UGPhone.
for attempt=1,20 do
    if type(EggState)=="table" and type(Assets)=="table" then break end
    task.wait(1)
    EggState,eggStatus=module({"Client","EggState"})
    Assets,assetStatus=module({"Data","Assets"})
end
local DIR = type(Assets)=="table" and type(Assets.Directory)=="table" and Assets.Directory or {}
local SPECS = type(HalloweenPets)=="table" and type(HalloweenPets.Specs)=="table" and HalloweenPets.Specs or {}

-- Indice: un alias ambiguo NO identifica una especie.
local index = {}
local function addAlias(name, asset, id)
    local k = norm(name)
    if k == "" or type(asset) ~= "table" then return end
    local old = index[k]
    if old == nil then
        index[k] = {asset=asset, id=tostring(id)}
    elseif old ~= false and old.id ~= tostring(id) then
        index[k] = false
    end
end
for id, data in pairs(DIR) do
    if type(data)=="table" then
        addAlias(id, data, id)
        addAlias(data.DisplayName, data, id)
    end
end
for key, spec in pairs(SPECS) do
    if type(spec)=="table" then
        local id = tostring(spec.Id or key)
        local data = DIR[id] or DIR[key]
        if type(data)=="table" then
            addAlias(id, data, id)
            addAlias(key, data, id)
            addAlias(spec.EggSource, data, id)
            -- EggModel puede ser compartido por muchas especies.
            addAlias(spec.EggModel, data, id)
        end
    end
end
local function findAsset(source)
    local k = norm(source)
    if k == "" or k == "halloweenegg" then return nil end
    local match = index[k]
    if type(match)=="table" then return match.asset, match.id end
    local direct = DIR[tostring(source)]
    if type(direct)=="table" then return direct, tostring(source) end
    return nil
end
local function rarity(asset)
    local r = type(asset)=="table" and asset.Rarity or nil
    if type(r)~="table" then return "Desconocida", false end
    local top = TOP[norm(r._id)] or TOP[norm(r.DisplayName)]
    return top or tostring(r.DisplayName or r._id or "Desconocida"), top~=nil
end
local function scaleFactor(scale)
    if scale > 5 then return (scale/5)^1.2 * 19.637875755794113 end
    return scale^1.85
end
local function earnings(asset, scale, muts)
    local base = type(asset)=="table" and tonumber(asset.EarningRate) or nil
    if not base then return nil end
    local mult = 1
    if type(muts)=="table" and type(Mutations)=="table"
        and type(Mutations.EarningsFor)=="function" then
        local ok, value = pcall(Mutations.EarningsFor, muts)
        if ok and type(value)=="number" and value>0 then mult=value end
    end
    return base * scaleFactor(scale) * mult
end
local function weight(id, scale)
    if type(EggRecords)=="table" and type(EggRecords.WeightKgForScale)=="function" then
        local ok, n = pcall(EggRecords.WeightKgForScale, id, scale)
        if ok then return tonumber(n) end
    end
    return nil
end
local function mutationNames(muts)
    if type(muts)~="table" then return "Sin datos" end
    local a = {}
    for k,v in pairs(muts) do
        if v==true then table.insert(a, tostring(k))
        elseif type(v)=="string" then table.insert(a, v) end
    end
    table.sort(a)
    return #a==0 and "Ninguna" or table.concat(a, ", ")
end
local function money(n)
    if type(n)~="number" then return "No disponible" end
    local units = {"", "K", "M", "B", "T", "Qa", "Qi"}
    local i = 1
    while math.abs(n)>=1000 and i<#units do
        n=n/1000
        i=i+1
    end
    return string.format("%.2f%s", n, units[i])
end
local function getScale(model)
    if model:IsA("Model") then
        local ok, n = pcall(function() return model:GetScale() end)
        if ok and type(n)=="number" then return n end
    end
    return 1
end
local function halloweenZone(obj)
    local attr = obj:GetAttribute("Zone")
    if attr ~= nil then return tostring(attr) end
    local dimension = workspace:FindFirstChild("HalloweenDimension")
    local zones = dimension and dimension:FindFirstChild("Zones")
    if zones then
        local ok, pos = pcall(function()
            return obj:IsA("Model") and obj:GetPivot().Position or obj.Position
        end)
        if ok and typeof(pos)=="Vector3" then
            for i=3,1,-1 do
                local part=zones:FindFirstChild("Zone"..i)
                if part and part:IsA("BasePart") then
                    local p=part.CFrame:PointToObjectSpace(pos)
                    if math.abs(p.X)<=part.Size.X/2 and math.abs(p.Z)<=part.Size.Z/2 then
                        return tostring(i)
                    end
                end
            end
        end
    end
    return "?"
end
local knownNames = {} -- recuerda PreparedSourceName si cambia en esta sesion
local function collect()
    local rows, pending, scopes = {}, {}, {}
    local counts = {}
    for _,zone in ipairs(ORDER) do counts[zone]=0 end
    local d={records=0,global="NO",models=0,source=0,unknown=0,flag=0,prompts=0,identified=0}
    local seen={}

    if type(EggState)=="table" and type(EggState.ReadFieldEggs)=="function" then
        local ok, snap = pcall(EggState.ReadFieldEggs)
        if ok and type(snap)=="table" and type(snap.Records)=="table" then
            d.global="SI"
            table.insert(scopes,"GLOBAL")
            for key,rec in pairs(snap.Records) do
                if type(rec)=="table" then
                    d.records=d.records+1
                    local zone=AREAS[norm(rec.AreaId)]
                    local state=tostring(rec.State or "?")
                    if zone and (state=="Slot" or state=="Dropped") then
                        local uid=tostring(rec.Uid or key)
                        if not seen["G/"..uid] then
                            seen["G/"..uid]=true
                            local asset,id=findAsset(rec.AssetCategory)
                            local r,top=rarity(asset)
                            if top then
                                local scale=tonumber(rec.AssetScale) or 1
                                local muts=type(rec.Mutations)=="table" and rec.Mutations or {}
                                table.insert(rows,{
                                    name=tostring(asset.DisplayName or id), rarity=r, zone=zone,
                                    uid=uid, status=state, cash=earnings(asset,scale,muts),
                                    kg=weight(id,scale), scale=scale, muts=mutationNames(muts),
                                    source="GLOBAL"
                                })
                                counts[zone]=counts[zone]+1
                            elseif not asset then
                                table.insert(pending,"GLOBAL | "..zone.." | sin catalogo: "..tostring(rec.AssetCategory))
                            end
                        end
                    end
                end
            end
        else
            d.global="ERROR/NO DISPONIBLE"
        end
    end

    local dim=workspace:FindFirstChild("HalloweenDimension")
    local eggs=dim and dim:FindFirstChild("WorldEggs")
    d.folder=eggs and "SI" or "NO"
    if eggs then
        table.insert(scopes,"HALLOWEEN")
        for idx,obj in ipairs(eggs:GetChildren()) do
            d.models=d.models+1
            local uid=tostring(obj:GetAttribute("HalloweenEggUid") or ("sin-uid-"..idx))
            local source=obj:GetAttribute("PreparedSourceName")
            if source and tostring(source)~="" then
                knownNames[uid]=tostring(source)
            else
                source=knownNames[uid]
            end
            local prompt=obj:FindFirstChild("StealPrompt",true)
            local promptOn=prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled==true
            local canPick=obj:GetAttribute("HalloweenEggCanPickUp")==true
            if promptOn then d.prompts=d.prompts+1 end
            if canPick then d.flag=d.flag+1 end
            local zone="Halloween Z"..halloweenZone(obj)
            if not source or norm(source)=="halloweenegg" then
                d.unknown=d.unknown+1
                table.insert(pending,"HALLOWEEN | "..zone.." | nombre no replicado | UID "..uid.." | CanPickUp="..tostring(canPick))
            else
                d.source=d.source+1
                local asset,id=findAsset(source)
                local r,top=rarity(asset)
                if asset then d.identified=d.identified+1 end
                local status=promptOn and "PROMPT ACTIVO" or
                    (canPick and "CanPickUp=true; prompt no activo" or "Recogida no confirmada")
                if top and not seen["H/"..uid] then
                    seen["H/"..uid]=true
                    local scale=getScale(obj)
                    table.insert(rows,{
                        name=tostring(asset.DisplayName or source), rarity=r, zone=zone,
                        uid=uid, status=status, cash=earnings(asset,scale,nil),
                        kg=nil, scale=scale, muts="No expuestas", source="HALLOWEEN"
                    })
                    counts.Halloween=counts.Halloween+1
                elseif not asset then
                    table.insert(pending,"HALLOWEEN | "..zone.." | "..tostring(source).." | sin catalogo | UID "..uid)
                end
            end
        end
    end

    table.sort(rows,function(a,b)
        if (a.cash or -1)==(b.cash or -1) then return a.uid<b.uid end
        return (a.cash or -1)>(b.cash or -1)
    end)
    local out={
        "=== PVFINDER V3 | CUATRO RAREZAS EN TODOS LOS BIOMAS PERMITIDOS ===",
        "PlaceId: "..tostring(game.PlaceId),
        "JobId: "..tostring(game.JobId),
        "Registro global: "..d.global.." | Registros: "..d.records,
        "Halloween WorldEggs: "..d.folder,
        "Halloween modelos: "..d.models,
        "Halloween con nombre de mascota: "..d.source,
        "Halloween sin nombre de mascota: "..d.unknown,
        "Halloween identificados en catalogo: "..d.identified,
        "Halloween CanPickUp=true: "..d.flag,
        "Halloween prompts activos: "..d.prompts,
        "Modulos: EggState="..eggStatus.." | Assets="..assetStatus.." | HalloweenPets="..halloweenStatus,
        "TOP detectados en total: "..#rows,
        "Filtro: Cosmic, Secret, Eternal, Divine",
        "",
        "=== TOP 4 RAREZAS | INGRESO DESCENDENTE ==="
    }
    local byRarity={Cosmic=0,Secret=0,Eternal=0,Divine=0}
    for _,item in ipairs(rows) do
        if byRarity[item.rarity] ~= nil then byRarity[item.rarity]=byRarity[item.rarity]+1 end
    end
    table.insert(out,"Cosmic: "..byRarity.Cosmic.." | Secret: "..byRarity.Secret)
    table.insert(out,"Eternal: "..byRarity.Eternal.." | Divine: "..byRarity.Divine)
    if #rows==0 then table.insert(out,"No hay huevos confirmados de esas cuatro rarezas en los datos recibidos.") end
    for i,item in ipairs(rows) do
        table.insert(out,"")
        table.insert(out,tostring(i)..". "..item.name.." | "..item.rarity.." | "..item.zone)
        table.insert(out,"Ingreso calculado: $"..money(item.cash).."/s")
        table.insert(out,"Estado: "..item.status.." | Fuente: "..item.source)
        table.insert(out,"Peso: "..(item.kg and string.format("%.2f kg",item.kg) or "No disponible"))
        table.insert(out,"Escala: "..tostring(item.scale).." | Mutacion: "..item.muts)
        table.insert(out,"UID: "..item.uid)
    end
    table.insert(out,"")
    table.insert(out,"=== TOTAL TOP POR BIOMA ===")
    for _,zone in ipairs(ORDER) do
        table.insert(out,zone..": "..counts[zone])
    end
    table.insert(out,"")
    table.insert(out,"=== PENDIENTES / IDENTIDAD DESCONOCIDA ===")
    if #pending==0 then table.insert(out,"Ninguno") end
    for _,item in ipairs(pending) do table.insert(out,item) end
    table.insert(out,"")
    table.insert(out,"Todos los TOP identificados: biomas permitidos + Halloween.")
    table.insert(out,"Solo estados Slot/Dropped para los huevos de campo.")
    table.insert(out,"Halloween: un modelo detectado no garantiza recogida.")
    table.insert(out,"CanPickUp=true es un indicador, NO prompt confirmado.")
    table.insert(out,"No accede a informacion exclusiva del servidor.")
    return table.concat(out,"\n"),rows,scopes,#pending
end


-- REPORTERO V4: todos los huevos de las cuatro rarezas, no solo el #1.
-- No cambia el juego, no recoge huevos, no envia remotos.
local HttpService=game:GetService("HttpService")
local endpoint="https://pvfinder.onrender.com/api/collect/snapshot"
local req=request or http_request or (syn and syn.request) or (http and http.request)
local env=(type(getgenv)=="function" and getgenv()) or _G
local token=env.PVFINDER_COLLECTOR_TOKEN
env.PVFINDER_COLLECTOR_TOKEN=nil
if type(token)~="string" or #token<35 or #token>160
    or not token:match("^pvf_[%w_%-]+$") then
    warn("[PVFinder V4] Falta la key pvf_ de este recolector.")
    return
end
if type(req)~="function" then
    warn("[PVFinder V4] Este cliente no ofrece request HTTP.")
    return
end
local job=tostring(game.JobId or "")
local place=tonumber(game.PlaceId)
if #job~=36 or not job:match("^[%x%-]+$") or not place or place<1 then
    warn("[PVFinder V4] JobId o PlaceId invalido.")
    return
end
-- Detener el reportero V3 en esta misma sesion, evitando que borre informes V4.
env.PVFINDER_HEADLESS_RUN_ID=nil
local runId=tostring({})
env.PVFINDER_FULL_RUN_ID=runId
local status={state="ON",scans=0,detected=0,accepted=0,removed=0,pending=0}
env.PVFINDER_FULL_STATUS=status
local active=true
local changed=true
local function awaken() changed=true end
local bound=setmetatable({}, {__mode="k"})
local function watch(folder)
    if not folder or bound[folder] then return end
    bound[folder]=true
    folder.ChildAdded:Connect(awaken)
    folder.ChildRemoved:Connect(awaken)
end
watch(workspace:FindFirstChild("AreaEggSlotsClient"))
local dimension=workspace:FindFirstChild("HalloweenDimension")
local function watchHalloween(node)
    if not node or bound[node] then return end
    bound[node]=true
    watch(node:FindFirstChild("WorldEggs"))
    node.ChildAdded:Connect(function(child)
        if child.Name=="WorldEggs" then watch(child);awaken() end
    end)
end
watchHalloween(dimension)
workspace.ChildAdded:Connect(function(node)
    if node.Name=="AreaEggSlotsClient" then watch(node);awaken() end
    if node.Name=="HalloweenDimension" then watchHalloween(node);awaken() end
end)
local function finite(n)
    return type(n)=="number" and n==n and n>=0 and n<1e18
end
local function submit(rows,scopes,pending)
    if #scopes==0 then status.state="ESPERANDO_FUENTES";return end
    local items={}
    for _,row in ipairs(rows) do
        local uid=tostring(row.uid or "")
        if uid~="" and not uid:match("^sin%-uid%-")
           and (row.rarity=="Cosmic" or row.rarity=="Secret"
                or row.rarity=="Eternal" or row.rarity=="Divine") then
            local income=finite(row.cash) and row.cash or nil
            local kg=finite(row.kg) and row.kg or nil
            table.insert(items,{
                egg_id=tostring(row.source).."/"..uid,
                egg_name=tostring(row.name),
                rarity=tostring(row.rarity),
                biome=tostring(row.zone),
                income_per_second=income,
                income_type=income and "ESTIMADO" or "NO_DISPONIBLE",
                weight_kg=kg,
                mutation=tostring(row.muts or "No disponible")
            })
        end
    end
    status.detected=#items
    status.pending=pending or 0
    if #items>500 then
        status.state="ERROR_MUCHOS_HUEVOS"
        warn("[PVFinder V4] Hay "..#items.." huevos; maximo 500 por informe.")
        return
    end
    local ok,payload=pcall(HttpService.JSONEncode,HttpService,{
        server_id=job,place_id=place,items=items,scopes=scopes
    })
    if not ok then status.state="ERROR_JSON";return end
    local success,response=pcall(req,{
        Url=endpoint,Method="POST",
        Headers={["Content-Type"]="application/json",
                 ["Authorization"]="Bearer "..token},
        Body=payload
    })
    if not success or type(response)~="table" then
        status.state="ERROR_RED";return
    end
    local code=tonumber(response.StatusCode or response.Status or 0) or 0
    if code==401 or code==403 then
        active=false;status.state="KEY_RECHAZADA"
        warn("[PVFinder V4] Key de recolector invalida o revocada.")
        return
    end
    if code~=200 then
        status.state="HTTP_"..tostring(code)
        warn("[PVFinder V4] "..status.state..", se reintentara")
        return
    end
    local parsed,result=pcall(HttpService.JSONDecode,HttpService,response.Body or "{}")
    if not parsed or type(result)~="table" or result.ok~=true then
        status.state="ERROR_RESPUESTA";return
    end
    status.state="ON"
    status.accepted=tonumber(result.accepted) or 0
    status.removed=tonumber(result.removed) or 0
    status.last_success=os.time()
    print("[PVFinder V4] "..status.accepted.." huevos enviados; "..
          status.removed.." retirados. JobId="..job)
end
print("[PVFinder V4] Escaneo completo de 4 rarezas: 5 s y eventos de aparicion.")
local lastScan=-5
task.spawn(function()
    while active and env.PVFINDER_FULL_RUN_ID==runId do
        local t=os.clock()
        if (changed or t-lastScan>=5) and t-lastScan>=2 then
            changed=false;lastScan=t
            status.scans=status.scans+1
            local ok,_,rows,scopes,pending=pcall(collect)
            if ok and type(rows)=="table" and type(scopes)=="table" then
                submit(rows,scopes,pending)
            else
                status.state="ERROR_LECTURA"
            end
        end
        task.wait(0.5)
    end
    if env.PVFINDER_FULL_RUN_ID==runId then status.state="OFF" end
end)
