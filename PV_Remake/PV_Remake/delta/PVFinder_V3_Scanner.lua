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
    local rows, pending = {}, {}
    local counts = {}
    for _,zone in ipairs(ORDER) do counts[zone]=0 end
    local d={records=0,global="NO",models=0,source=0,unknown=0,flag=0,prompts=0,identified=0}
    local seen={}

    if type(EggState)=="table" and type(EggState.ReadFieldEggs)=="function" then
        local ok, snap = pcall(EggState.ReadFieldEggs)
        if ok and type(snap)=="table" and type(snap.Records)=="table" then
            d.global="SI"
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
    return table.concat(out,"\n")
end

-- PANEL MOVIL: DOS BOTONES
local parent=me:WaitForChild("PlayerGui")
if type(gethui)=="function" then
    local ok,value=pcall(gethui)
    if ok and typeof(value)=="Instance" then parent=value end
end
local old=parent:FindFirstChild("PVFinderV3TopGlobal")
if old then old:Destroy() end
local gui=Instance.new("ScreenGui")
gui.Name="PVFinderV3TopGlobal"
gui.DisplayOrder=220
gui.ResetOnSpawn=false
gui.Parent=parent
local frame=Instance.new("Frame")
frame.Size=UDim2.new(.92,0,.64,0)
frame.Position=UDim2.fromScale(.5,.5)
frame.AnchorPoint=Vector2.new(.5,.5)
frame.BackgroundColor3=Color3.fromRGB(18,23,36)
frame.Active=true
frame.Parent=gui
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)
local constraint=Instance.new("UISizeConstraint",frame)
constraint.MaxSize=Vector2.new(510,670)
local title=Instance.new("TextLabel",frame)
title.Size=UDim2.new(1,-12,0,42)
title.Position=UDim2.fromOffset(6,3)
title.BackgroundTransparency=1
title.Text="PVFINDER V3 | 4 RAREZAS + HALLOWEEN"
title.TextColor3=Color3.new(1,1,1)
title.Font=Enum.Font.GothamBold
title.TextScaled=true
title.Active=true
local function button(name,x)
    local b=Instance.new("TextButton",frame)
    b.Size=UDim2.new(.47,0,0,40)
    b.Position=UDim2.new(x,0,0,48)
    b.Text=name
    b.Font=Enum.Font.GothamBold
    b.TextSize=14
    b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=Color3.fromRGB(49,102,191)
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    return b
end
local scan=button("ESCANEAR",.02)
local copy=button("COPIAR TODO",.51)
local scrolling=Instance.new("ScrollingFrame",frame)
scrolling.Position=UDim2.new(0,8,0,96)
scrolling.Size=UDim2.new(1,-16,1,-104)
scrolling.BackgroundColor3=Color3.fromRGB(9,13,21)
scrolling.ScrollBarThickness=5
scrolling.AutomaticCanvasSize=Enum.AutomaticSize.Y
scrolling.CanvasSize=UDim2.new(0,0,0,0)
Instance.new("UICorner",scrolling).CornerRadius=UDim.new(0,8)
local output=Instance.new("TextBox",scrolling)
output.Size=UDim2.new(1,-12,0,0)
output.AutomaticSize=Enum.AutomaticSize.Y
output.BackgroundTransparency=1
output.TextColor3=Color3.fromRGB(226,235,255)
output.TextXAlignment=Enum.TextXAlignment.Left
output.TextYAlignment=Enum.TextYAlignment.Top
output.TextWrapped=true
output.Font=Enum.Font.Code
output.TextSize=12
output.MultiLine=true
output.ClearTextOnFocus=false
output.TextEditable=true
output.Text="PVFinder iniciando..."

local latest=""
local busy=false
local function scanNow()
    if busy or not gui.Parent then return end
    busy=true
    local ok,value=pcall(collect)
    latest=ok and value or ("ERROR DE LECTURA:\n"..tostring(value))
    output.Text=latest
    busy=false
end
scan.MouseButton1Click:Connect(function() task.spawn(scanNow) end)
copy.MouseButton1Click:Connect(function()
    local fn=setclipboard or toclipboard
    if type(fn)=="function" then
        copy.Text=pcall(fn,latest) and "COPIADO" or "ERROR AL COPIAR"
    else
        copy.Text="COPIA MANUAL"
        output:CaptureFocus()
    end
    task.delay(2,function()
        if copy.Parent then copy.Text="COPIAR TODO" end
    end)
end)
local dragging,first,original,activeInput=false,nil,nil,nil
local begin=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch
       or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        first=input.Position
        original=frame.Position
        activeInput=input
    end
end)
local moving=UIS.InputChanged:Connect(function(input)
    if not dragging or not first then return end
    if input==activeInput or (activeInput and activeInput.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-first
        frame.Position=UDim2.new(original.X.Scale,original.X.Offset+d.X,
            original.Y.Scale,original.Y.Offset+d.Y)
    end
end)
local ending=UIS.InputEnded:Connect(function(input)
    if input==activeInput then dragging=false; activeInput=nil end
end)
gui.Destroying:Connect(function()
    begin:Disconnect()
    moving:Disconnect()
    ending:Disconnect()
end)
task.spawn(function()
    while gui.Parent do
        scanNow()
        task.wait(10)
    end
end)