-- PVFINDER V36.2 | ESCANER + PLACEID/JOBID + API LIVE FEED + JOIN
-- Solo lectura de objetos replicados en este cliente. NO ejecuta remotos.
-- Filtro: Cosmic / Secret / Eternal / Divine.
-- Ingresos base V18 = referencias historicas, NO datos actuales confirmados.
-- No agrupar por nombre, ruta ni UID: cada instancia es un ejemplar distinto.
-- HTTP HTTPS a API propia; admite key compartida o CONFIG FEED persistente.
-- El enlace JOIN es un INTENTO a la instancia, no una comprobacion de que sigue activa.

local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local HttpService=game:GetService("HttpService")
local player=Players.LocalPlayer
local guiParent=player:WaitForChild("PlayerGui")
local ENV=(getgenv and getgenv()) or _G

-- PVFINDER | CONFIGURACION DE BOTS (UNA SOLA KEY DE RECOLECTOR)
-- Al distribuir una copia privada de este archivo con la key real,
-- todos los bots que ejecuten esa misma copia la usaran automaticamente.
-- Alternativamente puedes guardarla una vez en CONFIG FEED por dispositivo
-- si tu ejecutor admite readfile/writefile.
-- NO uses aqui una key de administrador.
local SHARED_FEED_URL = ""   -- Ejemplo: https://tu-servidor.com/api/collect/batch
local SHARED_COLLECTOR_KEY = ""  -- Key real, formato pvf_...
local CONFIG_FILE = "PVFINDER/collector_config.json"

local function trimText(x)
    return tostring(x or ""):match("^%s*(.-)%s*$")
end
local function normalizeFeedURL(raw)
    raw=trimText(raw):gsub("/+$","")
    if not raw:match("^https://[%w%.%-]+") or raw:find("?",1,true) or raw:find("#",1,true) then return nil end
    if not raw:match("/api/collect/batch$") then
        if raw:match("/api/collect$") then raw=raw.."/batch"
        else raw=raw.."/api/collect/batch" end
    end
    return raw
end
local function validCollectorToken(key)
    return type(key)=="string" and key:match("^pvf_[%w_%-]+$")~=nil
end
local function loadSavedCollectorConfig()
    if type(readfile)~="function" then return end
    local ok,stored=pcall(readfile,CONFIG_FILE)
    if not ok or type(stored)~="string" then return end
    local parsedOk,data=pcall(function() return HttpService:JSONDecode(stored) end)
    if parsedOk and type(data)=="table" and validCollectorToken(data.token) and normalizeFeedURL(data.url) then
        ENV.PVFINDER_API_URL=normalizeFeedURL(data.url)
        ENV.PVFINDER_COLLECTOR_TOKEN=data.token
    end
end
local function saveCollectorConfig(url,token)
    if type(writefile)~="function" then return false end
    local ok=pcall(function()
        if type(makefolder)=="function" then pcall(makefolder,"PVFINDER") end
        writefile(CONFIG_FILE,HttpService:JSONEncode({url=url,token=token}))
    end)
    return ok
end

loadSavedCollectorConfig()
-- La configuracion compartida, cuando existe, tiene prioridad.
if validCollectorToken(SHARED_COLLECTOR_KEY) and normalizeFeedURL(SHARED_FEED_URL) then
    ENV.PVFINDER_API_URL=normalizeFeedURL(SHARED_FEED_URL)
    ENV.PVFINDER_COLLECTOR_TOKEN=SHARED_COLLECTOR_KEY
end
for _,fn in ipairs({"__EGGF_V34_STOP","__EGGF_V35_STOP","__PVF_V36_STOP","__PVF_V361_STOP","__PVF_V362_STOP"}) do
    if type(ENV[fn])=="function" then pcall(ENV[fn]) end
end
for _,n in ipairs({"EggFinderV34","EggFinderV35","EggFinderV330","PVFinderV36","PVFinderV361","PVFinderV362"}) do
    local g=guiParent:FindFirstChild(n)
    if g then g:Destroy() end
end

-- Estos identificadores describen el servidor DONDE ESTA ejecutandose este cliente.
-- No son un detector de servidores ajenos y el JobId puede estar vacio en Studio.
local SESSION_PLACE_ID=tonumber(game.PlaceId)
local SESSION_JOB_ID=tostring(game.JobId or "")
local function joinLink()
    if not SESSION_PLACE_ID or SESSION_PLACE_ID<=0 or SESSION_JOB_ID=="" then return "N/D" end
    -- Enlace a instancia reportada. Roblox puede no admitirlo o la instancia puede cerrarse.
    return "https://www.roblox.com/games/start?placeId="..tostring(SESSION_PLACE_ID)..
        "&gameInstanceId="..SESSION_JOB_ID
end
local TARGET={Cosmic=true,Secret=true,Eternal=true,Divine=true}
local ROOTS={
    {"Workspace.AreaEggSlotsClient","MUNDO"},
    {"Workspace.HalloweenDimension.WorldEggs","HALLOWEEN"},
    {"Workspace.Eggs","MUNDO"}
}
local function norm(x) return tostring(x or ""):lower():gsub("[^%w]",""):gsub("egg","") end
local function path(s)
    local o=game
    for part in s:gmatch("[^%.]+") do o=o and o:FindFirstChild(part) end
    return o
end
local function safeFull(o)
    local ok,v=pcall(function()return o:GetFullName()end)
    return ok and v or tostring(o.Name)
end
local function good(x) return type(x)=="number" and x==x and x>0 and x<math.huge end
local function number(v)
    if type(v)=="number" then return v end
    if type(v)=="string" then
        local s=v:gsub(",",""):gsub("%$",""):gsub("%s","")
        local a,b=s:match("^([%d%.]+)([KkMmBbTt]?)$")
        if a then return tonumber(a)*({[""]=1,K=1e3,k=1e3,M=1e6,m=1e6,B=1e9,b=1e9,T=1e12,t=1e12})[b] end
    end
    return nil
end
local function getField(obj,keys)
    local wanted={}
    for _,k in ipairs(keys) do wanted[k:lower()]=true end
    local function read(d)
        local ok,at=pcall(function()return d:GetAttributes()end)
        if ok then for k,v in pairs(at) do
            if wanted[tostring(k):lower()] and v~=nil then return v,"ATRIBUTO:"..k end
        end end
        if d:IsA("ValueBase") and wanted[d.Name:lower()] then
            local ok2,v=pcall(function()return d.Value end)
            if ok2 then return v,"VALUE:"..d.Name end
        end
    end
    local v,src=read(obj)
    if v~=nil then return v,src end
    for _,d in ipairs(obj:GetDescendants()) do
        v,src=read(d)
        if v~=nil then return v,src end
    end
    return nil,nil
end
local function getNum(o,keys)
    local v,s=getField(o,keys)
    return number(v),s
end
local function pos(o)
    local ok,v=pcall(function()
        if o:IsA("Model") then return o:GetPivot().Position end
        if o:IsA("BasePart") then return o.Position end
    end)
    return ok and v or nil
end
local function isGeneric(name)
    local n=tostring(name or "")
    return n:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")~=nil
        or ({egg=true,model=true,part=true,halloweenegg=true})[n:lower()]==true
        or n:find(":Slot_",1,true)~=nil
end
local function meshId(d)
    local ok,id=pcall(function()return d.MeshId end)
    return ok and tostring(id):match("%d+") or nil
end
local function fingerprint(o)
    local mesh,forms,parts={}, {}, {}
    local function add(d)
        if d:IsA("BasePart") then
            forms[#forms+1]=d.ClassName..":"..d.Name
            parts[#parts+1]=d
            if d:IsA("MeshPart") then local id=meshId(d); if id then mesh[id]=true end end
        elseif d:IsA("SpecialMesh") then local id=meshId(d); if id then mesh[id]=true end end
    end
    add(o)
    for _,d in ipairs(o:GetDescendants()) do add(d) end
    local ids={}
    for k in pairs(mesh) do ids[#ids+1]=k end
    table.sort(ids)
    table.sort(forms)
    return table.concat(ids,"+"),table.concat(forms,"|"),parts
end

-- Referencias de gradientes de los reportes V32.8/V32.9. INDICIO VISUAL.
local VISUAL={}
local function addR(r,names)
    for nm in names:gmatch("[^|]+") do VISUAL[norm(nm)]=r end
end
addR("Cosmic","Koi|Bronto|King Mammoth|Mantaris|Astral Jackalope|Spirit Panda|Scarecrow|Patchwork Imp|Haunted Scorpio|Hexed Pumpkin")
addR("Secret","Stag|Starry Fox|Centaur|Gargoyle|Pure Jellyfish|RazorFang|TRex|Yeti|Mutant Shark|Graveyard Brute|Pumpkin Golem|BloodBloom|Werewolf")
addR("Eternal","Oni Tiger|Celestial Sunlion|Pegasus|Gorilla King|Ghost Reaper|Shelltide Voyager|Soul Phantom|Gorillastein")
addR("Divine","Kitsune|Royal Skywhale|Voidseer Pumpkin")

-- Referencias comunitarias antiguas para ingreso BASE/s y masa BASE/kg.
-- NO son valores oficiales, ni se presume que sigan iguales en el juego.
local BASE_RAW=[=[
Chicken|1|8
Dog|2|25
Frog|3|3
Duckling|4|3
Jerboa|6|2
Bird|8|5
Catfish|12|35
Fennec|18|8
Burrowing Owl|35|8
Raccoon|45|19
Turtle|60|100
Camel|75|700
Chimpanzee|90|65
Toucan|110|5
Penguin|140|16
Lava Gecko|180|14
Parrotfish|220|5
Dodo|280|20
Fox|180|28
Bear|240|220
Swan|320|22
Tob Tobi Tob Tob|325|700
Crocodile|420|400
Walrus|600|200
Lava Frog|850|4
Swordfish|1100|250
Centapede|1500|6
Crane|4000|22
Brr Brr Patapim|1800|800
Axolotl|2800|28
Snake|3600|45
Gorilla|4800|190
Orangutini Ananassini|5500|140
Polar Bear|7000|650
Flaming Bull|9500|450
Lava Iguana|11000|400
Shark|15000|450
Pterodactyl|22000|180
Glyptodon|22500|3000
Cosmic Gecko|30000|18
Salamander|74000|30
Spideron|95000|600
Crustacia|130000|1000
Flame Sprite|225000|45000
Light Dove|225000|45000
Sand Spider|16000|120
Scorpion|18500|75
Spider|22000|120
Tiger|28000|260
Sabertooth Tiger|35000|350
Mammoth|42000|2000
Chillin Chilli|55000|30
Spirit Manta|75000|450
Orca|80000|1800
Terrorbird|110000|6000
Ankylosaurus|120000|2500
Cosmic Gorilla|180000|450
Bladehide|750000|1700
Leviathan|220000|5000
Royal Sphinx|280000|4000
King Mammoth|400000|25000
Whale Shark|700000|2000
Beluga Whale|850000|5000
Triceratops|1200000|3500
Bronto|1500000|35000
La Vacca Saturno Saturnita|2200000|740
Abyss Shark|2500000|60000
Giant Sloth|4000000|12000
Snowy Owl|7500000|20
Mantaris|11000000|1500
Koi|12000000|120
Stacked Turtle|12000000|300
Imp|16000000|9000
Sacred Moth|16000000|9000
Rhinotaur|17500000|35000
Demon Hound|25000000|9000
Holy Peacock|25000000|9000
Spiderpig|25000000|180
King Snake|3500000|10000
Yeti|5000000|1500
Cerberus|8000000|9000
Kraken|15000000|18000
Wendigo|15000000|12000
T-Rex|25000000|7500
Tralaledon|32000000|1000
Cosmic Skeleton Boss|45000000|1000
Cosmic Dragon|60000000|15000
Stag|145000000|180
Electric Eel|200000000|45
Gargoyle|225000000|10000
Pure Jellyfish|225000000|10000
Dunkleosteus|300000000|20000
RazorFang|350000000|12000
Centaur|350000000|12000
Sharkodile|350000000|30000
Nuceodile|500000000|6000
Skeletal Glyptodon|550000000|3000
Skeletal Terrorbird|750000000|6000
Eyeball Crab|825000000|1200
Skeletal Giant Sloth|900000000|12000
Ice Dragon|65000000|8500
Phoenix|85000000|2500
Lava Dragon|100000000|14000
Mosasaurus|180000000|30000
Eternal Lunar Dragon|250000000|60000
Oni Tiger|600000000|300
Terra Snapper|750000000|60000
Gorilla King|880000000|100000
Rhinobear|1000000000|20000
Pegasus|1300000000|65000
Skeleton Horse|1300000000|65000
Equinox|1800000000|65000
Unicorn|1000000000|1200
Kitsune|1800000000|260
Nightflame|3000000000|160000
ArchAngel|5000000000|120000
World Burner|5000000000|120000
Aetheron|6900000000|12000
Tung Tung Sahur|100|35
Bananita Dolphinita|400|300
Belula Beluga|40000|800
Mangolini Parrochini|800000|1500
Bomboclat Crocolat|20000000|7000
Strawberry Elephant|110000000|35000
]=]
local BASE={}
for line in BASE_RAW:gmatch("[^\r\n]+") do
    local n,i,w=line:match("^([^|]+)|([^|]+)|([^|]+)$")
    if n then BASE[norm(n)]={income=tonumber(i),weight=tonumber(w),src="GUIA_V18"} end
end
-- Capturas antiguas: orientativas; NO garantizan que sean ingreso base.
local EXTRA={
    hexedpumpkin={income=150e6,src="CAPTURA_V18"},
    hauntedscorpio={income=30e6,src="EXPERIMENTO_V18"},
    astraljackalope={income=30e6,weight=649,src="REFERENCIA_V18"},
    spiritpanda={income=68.1e6/(0.86^1.85),weight=1275/(0.86^3),src="CALIBRACION_UNA_CAPTURA_V32"}
}

local catalog,byName,byMesh,byForm={}, {}, {}, {}
local initialized=false
local function catalogAdd(o)
    local mk,fm,parts=fingerprint(o)
    local e={name=o.Name,key=norm(o.Name),inst=o,mesh=mk,form=fm,parts=parts}
    catalog[#catalog+1]=e
    byName[e.key]=byName[e.key] or {}
    byName[e.key][#byName[e.key]+1]=e
    if mk~="" then
        byMesh[mk]=byMesh[mk] or {}
        byMesh[mk][#byMesh[mk]+1]=e
    end
    if fm~="" then
        byForm[fm]=byForm[fm] or {}
        byForm[fm][#byForm[fm]+1]=e
    end
end
local function setupCatalog()
    for _,p in ipairs({"ReplicatedStorage.Assets.Models.Eggs","ReplicatedStorage.AssetModels"}) do
        local root=path(p)
        if root then
            for _,o in ipairs(root:GetDescendants()) do
                if (o:IsA("Model") or o:IsA("MeshPart")) and (o.Parent==root or o.Parent:IsA("Folder")) then
                    catalogAdd(o)
                end
            end
        end
    end
    initialized=true
end
local function distinct(entries)
    local seen,n= {},nil
    for _,e in ipairs(entries or {}) do
        if not seen[e.key] then
            if n and n~=e.key then return nil end
            n=e.key;seen[e.key]=true
        end
    end
    return n
end
local function identify(o)
    local prep=getField(o,{"PreparedSourceName","SourceName","PetName","MonsterName","EggName"})
    if type(prep)=="string" and prep~="" then
        local nm=prep:match("([^%.]+)$") or prep
        if norm(nm)~="" then return nm,"ATRIBUTO_ORIGEN" end
    end
    if not isGeneric(o.Name) then return o.Name,"NOMBRE_OBJETO" end
    local mesh,form=fingerprint(o)
    local k=mesh~="" and distinct(byMesh[mesh]) or nil
    if not k and form~="" then k=distinct(byForm[form]) end
    if k then
        local e=byName[k] and byName[k][1]
        return e and e.name or k,mesh~="" and "CATALOGO_MALLAS" or "CATALOGO_ESTRUCTURA"
    end
    return nil,"IDENTIDAD_DESCONOCIDA"
end
local function median(t)
    if #t==0 then return nil end
    table.sort(t)
    local n=#t
    return n%2==1 and t[(n+1)/2] or (t[n/2]+t[n/2+1])/2
end
local function scaleFor(o,name)
    local direct=getNum(o,{"SizeMultiplier","ScaleMultiplier","PetScale","ScaleFactor"})
    if good(direct) then return direct,"MULTIPLICADOR_REPLICADO" end
    local _,_,parts=fingerprint(o)
    local refs=byName[norm(name)] or {}
    local bestS,bestN=nil,0
    for _,ref in ipairs(refs) do
        local ratios={}
        local pool={}
        for _,p in ipairs(ref.parts) do
            local id=p:IsA("MeshPart") and (meshId(p) or "") or ""
            local key=p.ClassName..":"..p.Name..":"..id
            pool[key]=pool[key] or {}
            pool[key][#pool[key]+1]=p
        end
        for _,p in ipairs(parts) do
            local id=p:IsA("MeshPart") and (meshId(p) or "") or ""
            local key=p.ClassName..":"..p.Name..":"..id
            local matches=pool[key]
            if matches and #matches==1 then
                local q=matches[1]
                local pa={p.Size.X,p.Size.Y,p.Size.Z}
                local qa={q.Size.X,q.Size.Y,q.Size.Z}
                table.sort(pa);table.sort(qa)
                for i=1,3 do if qa[i]>0.01 then ratios[#ratios+1]=pa[i]/qa[i] end end
            end
        end
        local s=median(ratios)
        if good(s) and #ratios>=3 then
            local deviations={}
            for _,r in ipairs(ratios) do deviations[#deviations+1]=math.abs(r/s-1) end
            if (median(deviations) or 1)<=0.2 and #ratios>bestN then
                bestS,bestN=s,#ratios
            end
        end
    end
    if good(bestS) then return bestS,"GEOMETRIA_ESTIMADA" end
    return nil,"SIN_ESCALA"
end
local function moneyFormat(n)
    if not good(n) then return "N/D" end
    local units={"","K","M","B","T","Qa","Qi","Sx"}
    local i=1
    while n>=1000 and i<#units do n=n/1000;i=i+1 end
    return string.format("%.2f%s",n,units[i])
end
local function sizeFactor(s)
    if s<=5 then return s^1.85 end
    return 5^1.85*(s/5)^1.2
end
local function getZone(o,tag,anchors)
    if tag=="HALLOWEEN" then return "Halloween" end
    local z=getField(o,{"Biome","AreaName","ZoneName","Area","Region"})
    if type(z)=="string" and z~="" then return z end
    local prep=getField(o,{"PreparedSourceName"})
    if type(prep)=="string" and prep:find("NewEnchantedEggs",1,true) then return "Enchanted Forest" end
    local p=pos(o)
    if not p then return "SIN_ZONA" end
    -- Centros de zona vistos en escaneos anteriores; proximidad, no dato del servidor.
    local prev={{"Forest",597},{"Lake",744},{"Desert",950},{"Jungle",1182},
        {"Snow",1492},{"Volcano",1879},{"Abyss Ocean",2281},{"Prehistoric",2813},
        {"Cosmic",3392},{"Cherry Blossom",4028},{"Titan Temple",4798},
        {"Angels & Demons",5663},{"Enchanted Forest",6697}}
    for _,a in ipairs(prev) do
        if math.abs(p.X-a[2])<=80 then return a[1] end
    end
    local closest,dist=nil,math.huge
    for _,a in ipairs(anchors) do
        local d=math.abs(p.X-a.x)
        if d<dist then closest,dist=a.name,d end
    end
    return dist<=75 and (closest=="Light Dark" and "Angels & Demons" or closest) or "SIN_ZONA"
end
local function anchorList()
    local result={}
    local a=path("Workspace.World.Areas.GuardAreas")
    if a then for _,obj in ipairs(a:GetChildren()) do
        local p=pos(obj)
        if not p and obj:IsA("Folder") then
            local child=obj:FindFirstChildWhichIsA("BasePart",true)
            p=child and child.Position or nil
        end
        if p then result[#result+1]={name=obj.Name,x=p.X} end
    end end
    return result
end
-- Se usan las rarezas reales del ejemplar, las etiquetas replicadas y
-- el atributo del AssetModel. El indice visual queda como indicio historico.
local RARITIES={"Cosmic","Secret","Eternal","Divine"}
local RARITY_ANY={
    Common=true,Uncommon=true,Rare=true,Epic=true,Legendary=true,
    Mythic=true,Cosmic=true,Secret=true,Eternal=true,Divine=true
}
local function canonical(v)
    if type(v)~="string" then return nil end
    for k in pairs(RARITY_ANY) do if norm(k)==norm(v) then return k end end
    return nil
end
local function catalogRarity(name)
    local unique,conflict=nil,false
    for _,e in ipairs(byName[norm(name)] or {}) do
        local obj=e.inst
        local ok,at=pcall(function()return obj:GetAttributes()end)
        if ok then
            for k,v in pairs(at) do
                if (norm(k)=="rarity" or norm(k)=="petrarity" or norm(k)=="eggrarity") then
                    local r=canonical(v)
                    if r then
                        if unique and unique~=r then conflict=true end
                        unique=r
                    end
                end
            end
        end
    end
    return conflict and nil or unique, conflict
end
local function uiRarity(o)
    -- Solo labels dentro de ESTE huevo: nunca lee la ficha de otro huevo.
    local answer,ambiguous=nil,false
    for _,d in ipairs(o:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local r=canonical(d.Text)
            if r then
                if answer and answer~=r then ambiguous=true end
                answer=r
            end
        end
    end
    return ambiguous and nil or answer
end
local function extract(o,name,zone)
    local raw,rawSrc=getField(o,{"Rarity","PetRarity","EggRarity","RarityName","MonsterRarity"})
    local direct=canonical(raw)
    local onEggUI=uiRarity(o)
    local model,modelConflict=catalogRarity(name)
    local visual=VISUAL[norm(name)]
    local known={}
    if direct then known[#known+1]={r=direct,s="ATRIBUTO_EJEMPLAR"} end
    if onEggUI then known[#known+1]={r=onEggUI,s="ETIQUETA_EJEMPLAR"} end
    if model then known[#known+1]={r=model,s="ATRIBUTO_MODELO"} end
    if visual then known[#known+1]={r=visual,s="INDICIO_INDICE_V32"} end
    local chosen,source=nil,"SIN_RAREZA"
    for _,k in ipairs(known) do
        if TARGET[k.r] then chosen=k.r;source=k.s;break end
    end
    local different=modelConflict
    local allNames={}
    for _,k in ipairs(known) do
        allNames[#allNames+1]=k.s.."="..k.r
        if chosen and k.r~=chosen then different=true end
    end
    -- Nunca etiquetar como confirmado si una fuente discrepa.
    if different and chosen then source=source.."_CONFLICTO" end
    if not chosen then
        return {rarity=nil,source="SIN_RAREZA",known=table.concat(allNames,"; "),
            conflict=different,rawRarity=direct or onEggUI or model or visual}
    end
    local baseI,srcI=getNum(o,{"BaseIncomePerSecond","BaseMoneyPerSecond","BaseEarningsPerSecond","BaseIncome"})
    local directI,srcD=getNum(o,{"IncomePerSecond","MoneyPerSecond","CashPerSecond","EarningsPerSecond","PerSecond"})
    local baseW,srcW=getNum(o,{"BaseWeightKg","BaseMassKg","BaseWeight"})
    local directW,srcDW=getNum(o,{"WeightKg","MassKg","PetWeightKg","PetWeight","Weight"})
    local base=BASE[norm(name)] or EXTRA[norm(name)]
    if not good(baseI) and base and good(base.income) then baseI=base.income;srcI=base.src end
    if not good(baseW) and base and good(base.weight) then baseW=base.weight;srcW=base.src end
    local scale,scaleSrc=scaleFor(o,name)
    if good(directW) and good(baseW) then
        local massScale=(directW/baseW)^(1/3)
        if good(massScale) then scale,scaleSrc=massScale,"MASA_REPLICADA_A_ESCALA_V18" end
    end
    local mutation=getField(o,{"Mutation","MutationName","MutationType"})
    local mult=getNum(o,{"MutationMultiplier","IncomeMultiplier"})
    local income,method=nil,"SIN_INGRESO"
    if good(directI) then income=directI;method="DIRECTO_REPLICADO"
    elseif good(baseI) then
        income=baseI*(good(scale) and sizeFactor(scale) or 1)*(good(mult) and mult or 1)
        method=(srcI=="GUIA_V18" or (base and srcI==base.src)) and "ESTIMACION_HISTORICA" or "BASE_REPLICADA_CALCULADA"
        if not good(scale) then method=method.."_ESCALA_DESCONOCIDA" end
        if not good(mult) then method=method.."_MUTACION_NO_VERIFICADA" end
    end
    local weight,weightSrc=directW,(good(directW) and (srcDW or "DIRECTO") or "SIN_DATO")
    if not good(weight) and good(baseW) then
        weight=baseW*(good(scale) and scale^3 or 1)
        weightSrc=good(scale) and "MASA_ESTIMADA_POR_ESCALA" or "MASA_BASE_SIN_ESCALA"
    end
    return {rarity=chosen,source=source,conflict=different,visual=visual,
        known=table.concat(allNames,"; "),income=income,method=method,
        baseIncome=baseI,baseIncomeSource=srcI,weight=weight,weightSource=weightSrc,
        baseWeight=baseW,scale=scale,scaleSource=scaleSrc,mutation=mutation,mult=mult}
end

-- PVFINDER V36: interfaz inspirada en el boceto del usuario.
-- LIVE FEED muestra exclusivamente ejemplares realmente visibles en este cliente.
-- Los ingresos historicos se rotulan ESTIMADOS; nunca son cifras confirmadas.
local gui=Instance.new("ScreenGui")
gui.Name="PVFinderV362"
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=false
gui.DisplayOrder=950
gui.Parent=guiParent

local C={
    bg=Color3.fromRGB(8,11,19),panel=Color3.fromRGB(14,19,30),
    inset=Color3.fromRGB(9,14,23),edge=Color3.fromRGB(91,103,157),
    fg=Color3.fromRGB(241,245,255),dim=Color3.fromRGB(167,182,207),
    purple=Color3.fromRGB(128,102,255),blue=Color3.fromRGB(59,152,244),
    green=Color3.fromRGB(85,221,157),orange=Color3.fromRGB(255,174,83)
}
local function el(class,parent,props)
    local o=Instance.new(class)
    for k,v in pairs(props or {}) do o[k]=v end
    o.Parent=parent
    return o
end
local function round(o,r)
    el("UICorner",o,{CornerRadius=UDim.new(0,r or 8)})
end
local function outline(o,color,size)
    el("UIStroke",o,{Color=color or C.edge,Thickness=size or 1,Transparency=.22})
end
local function label(parent,text,size,props)
    local p={BackgroundTransparency=1,Text=tostring(text or ""),
        TextColor3=C.fg,TextSize=size or 12,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center}
    for k,v in pairs(props or {}) do p[k]=v end
    return el("TextLabel",parent,p)
end
local function button(parent,txt,props)
    local p={Text=txt,Font=Enum.Font.GothamBold,TextSize=12,
        TextColor3=C.fg,BackgroundColor3=C.panel,BorderSizePixel=0,
        AutoButtonColor=true}
    for k,v in pairs(props or {}) do p[k]=v end
    local b=el("TextButton",parent,p)
    round(b,7)
    outline(b,C.edge,.8)
    return b
end
local function movable(handle,target)
    local dragging=false
    local starting,first
    local endConn=handle.InputBegan:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true;starting=inp.Position;first=target.Position
            inp.Changed:Connect(function()
                if inp.UserInputState==Enum.UserInputState.End then dragging=false end
            end)
        end
    end)
    local moveConn=UIS.InputChanged:Connect(function(inp)
        if dragging and starting and (inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseMovement) then
            local delta=inp.Position-starting
            target.Position=UDim2.new(first.X.Scale,first.X.Offset+delta.X,first.Y.Scale,first.Y.Offset+delta.Y)
        end
    end)
    return {endConn,moveConn}
end

local main=el("Frame",gui,{Size=UDim2.new(.96,0,.53,0),Position=UDim2.new(.02,0,.055,0),
    BackgroundColor3=C.bg,BorderSizePixel=0,Active=true})
round(main,11);outline(main,C.edge,1.2)
local top=el("Frame",main,{Size=UDim2.new(1,-12,0,43),Position=UDim2.fromOffset(6,3),
    BackgroundTransparency=1,Active=true})
local heading=label(top,"PVFINDER",20,{Size=UDim2.new(.56,0,1,0),Font=Enum.Font.GothamBold})
local cap=label(top,"EN ESTA SESION",9,{Size=UDim2.new(.43,-4,1,0),Position=UDim2.new(.57,0,0,0),
    TextColor3=C.green,TextXAlignment=Enum.TextXAlignment.Right})
local line=el("Frame",main,{Size=UDim2.new(1,-16,0,1),Position=UDim2.fromOffset(8,48),BackgroundColor3=C.edge,BorderSizePixel=0})
local side=el("Frame",main,{Position=UDim2.fromOffset(7,56),Size=UDim2.new(.34,-9,1,-64),BackgroundTransparency=1})
local divider=el("Frame",main,{Position=UDim2.new(.34,0,0,53),Size=UDim2.new(0,1,1,-60),BackgroundColor3=C.edge,BorderSizePixel=0})
local right=el("Frame",main,{Position=UDim2.new(.34,5,0,54),Size=UDim2.new(.66,-13,1,-61),BackgroundTransparency=1})
local logTab=button(side,"LOGS",{Position=UDim2.new(0,0,0,4),Size=UDim2.new(1,-3,0,36),TextSize=11})
local statsTab=button(side,"ESTADISTICAS",{Position=UDim2.new(0,0,0,47),Size=UDim2.new(1,-3,0,36),TextSize=10})
local cmdTab=button(side,"PANELCOMMANDS",{Position=UDim2.new(0,0,0,90),Size=UDim2.new(1,-3,0,42),TextSize=10})
local feedTab=button(right,"LIVE FEED",{Position=UDim2.fromOffset(0,0),Size=UDim2.new(.66,0,0,27),
    TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1,TextSize=14,BorderSizePixel=0})
local feedState=label(right,"",9,{Position=UDim2.new(.64,0,0,2),Size=UDim2.new(.36,0,0,23),
    TextColor3=C.green,TextXAlignment=Enum.TextXAlignment.Right})
local feedArea=el("ScrollingFrame",right,{Position=UDim2.fromOffset(0,34),Size=UDim2.new(1,0,1,-39),
    BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,
    CanvasSize=UDim2.new(),ScrollingDirection=Enum.ScrollingDirection.Y})
local stack=el("UIListLayout",feedArea,{FillDirection=Enum.FillDirection.Vertical,Padding=UDim.new(0,5),
    HorizontalAlignment=Enum.HorizontalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder})
stack:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    feedArea.CanvasSize=UDim2.new(0,0,0,stack.AbsoluteContentSize.Y+5)
end)

-- Consola inferior (se abre/cierra con PANELCOMMANDS).
local console=el("Frame",gui,{Position=UDim2.new(.035,0,.605,0),Size=UDim2.new(.93,0,.335,0),
    BackgroundColor3=C.bg,BorderSizePixel=0,Active=true})
round(console,10);outline(console,C.edge,1.2)
local consoleHead=el("Frame",console,{BackgroundTransparency=1,Position=UDim2.fromOffset(8,4),
    Size=UDim2.new(1,-16,0,30),Active=true})
local cmdTitle=label(consoleHead,"COMANDS DE PRUEBA",12,{Size=UDim2.new(.7,0,1,0),Font=Enum.Font.GothamBold,Active=true})
local configBtn=button(consoleHead,"CONFIG FEED",{Position=UDim2.new(.70,0,0,1),Size=UDim2.new(.30,0,1,-2),TextSize=9})
local consoleArea=el("ScrollingFrame",console,{Position=UDim2.fromOffset(8,38),Size=UDim2.new(1,-16,1,-84),
    BackgroundColor3=C.inset,ScrollBarThickness=4,BorderSizePixel=0,CanvasSize=UDim2.new()})
round(consoleArea,7);outline(consoleArea,C.edge,.8)
local output=el("TextBox",consoleArea,{Position=UDim2.fromOffset(6,5),Size=UDim2.new(1,-14,0,240),
    BackgroundTransparency=1,Text="Esperando escaneo...",Font=Enum.Font.Code,TextColor3=C.fg,
    TextSize=11,TextWrapped=true,MultiLine=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,TextEditable=true,ClearTextOnFocus=false})
local scanBtn=button(console,"ESCANEAR",{Position=UDim2.new(0,8,1,-41),Size=UDim2.new(.5,-12,0,34),
    BackgroundColor3=Color3.fromRGB(68,48,160),TextSize=13})
local copyBtn=button(console,"COPIAR TODO",{Position=UDim2.new(.5,4,1,-41),Size=UDim2.new(.5,-12,0,34),TextSize=12})
local status=label(console,"",9,{Position=UDim2.new(0,7,1,-7),Size=UDim2.new(1,-14,0,0)})
-- CONFIGURACION: nunca se incluye la credencial en logs, copias ni POST body.
-- El envio se activa con la key compartida o al guardar CONFIG FEED.
local apiUrl=normalizeFeedURL(ENV.PVFINDER_API_URL or "") or ""
local collectorToken=tostring(ENV.PVFINDER_COLLECTOR_TOKEN or "")
local sendingEnabled=(apiUrl~="" and validCollectorToken(collectorToken))
local uploadBusy=false
local lastUploadClock=-math.huge
local uploadMessage=sendingEnabled and "API: CONFIGURADA" or "API: SIN CONFIGURAR"
local triggerAfterSave=nil

local configPanel=el("Frame",gui,{Position=UDim2.new(.08,0,.28,0),Size=UDim2.new(.84,0,0,216),
    BackgroundColor3=C.panel,BorderSizePixel=0,Active=true,Visible=false,ZIndex=50})
round(configPanel,10);outline(configPanel,C.purple,1.4)
local cfgTitle=label(configPanel,"PVFINDER | CONECTAR LIVE FEED",12,{Position=UDim2.fromOffset(12,6),
    Size=UDim2.new(1,-24,0,25),Font=Enum.Font.GothamBold,ZIndex=51})
label(configPanel,"API HTTPS (tu web publicada):",10,{Position=UDim2.fromOffset(12,35),
    Size=UDim2.new(1,-24,0,16),TextColor3=C.dim,ZIndex=51})
local urlInput=el("TextBox",configPanel,{Position=UDim2.new(0,12,0,54),Size=UDim2.new(1,-24,0,30),
    BackgroundColor3=C.inset,BorderSizePixel=0,TextColor3=C.fg,PlaceholderColor3=C.dim,
    Text=tostring(apiUrl),PlaceholderText="https://tudominio.com",
    Font=Enum.Font.Code,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,
    ClearTextOnFocus=false,TextEditable=true,ZIndex=51})
round(urlInput,5)
label(configPanel,"Credencial de RECOLECTOR (no de admin):",10,{Position=UDim2.fromOffset(12,90),
    Size=UDim2.new(1,-24,0,16),TextColor3=C.dim,ZIndex=51})
local tokenInput=el("TextBox",configPanel,{Position=UDim2.new(0,12,0,109),Size=UDim2.new(1,-24,0,30),
    BackgroundColor3=C.inset,BorderSizePixel=0,TextColor3=C.fg,PlaceholderColor3=C.dim,
    Text="",PlaceholderText=collectorToken~="" and "Credencial guardada en sesion" or "pvf_...",
    Font=Enum.Font.Code,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,
    ClearTextOnFocus=false,TextEditable=true,ZIndex=51})
round(tokenInput,5)
local configSave=button(configPanel,"GUARDAR Y ENVIAR",{Position=UDim2.new(0,12,0,146),
    Size=UDim2.new(.6,-16,0,31),BackgroundColor3=Color3.fromRGB(68,48,160),TextSize=11,ZIndex=51})
local configClose=button(configPanel,"CERRAR",{Position=UDim2.new(.6,0,0,146),
    Size=UDim2.new(.4,-12,0,31),TextSize=10,ZIndex=51})
local configInfo=label(configPanel,"Solo HTTPS. El token no aparecera en las copias.",9,
    {Position=UDim2.new(0,12,0,183),Size=UDim2.new(1,-24,0,23),
    TextColor3=C.dim,TextWrapped=true,ZIndex=51})
configBtn.MouseButton1Click:Connect(function() configPanel.Visible=not configPanel.Visible end)
configClose.MouseButton1Click:Connect(function() configPanel.Visible=false end)
configSave.MouseButton1Click:Connect(function()
    local raw=normalizeFeedURL(urlInput.Text)
    if not raw then
        configInfo.Text="URL invalida. Necesitas un dominio HTTPS publicado.";return
    end
    local key=tokenInput.Text~="" and tokenInput.Text or collectorToken
    if not validCollectorToken(key) then
        configInfo.Text="Pega la credencial pvf_ de PVFINDER ADMIN.";return
    end
    apiUrl,collectorToken=raw,key
    ENV.PVFINDER_API_URL=apiUrl
    ENV.PVFINDER_COLLECTOR_TOKEN=collectorToken
    local persisted=saveCollectorConfig(apiUrl,collectorToken)
    tokenInput.Text=""  -- No mantenerla visible en el panel de configuracion.
    tokenInput.PlaceholderText="Credencial guardada en sesion"
    sendingEnabled=true
    uploadMessage="API: ACTIVADA (pendiente de confirmar envio)"
    configInfo.Text=persisted and "Guardada en dispositivo; se recargara al iniciar." or "Guardada solo en sesion: tu ejecutor no permite archivo."
    configPanel.Visible=false
    if triggerAfterSave then triggerAfterSave() end
end)
local pages={"Esperando escaneo...","Sin datos."}
local full=""
local pageNum=1
local currentView="FEED"
local feedItems={top={},grouped={Cosmic={},Secret={},Eternal={},Divine={}},pending=0}
local statsText="Aun no hay datos."
local logsText="Aun no hay cambios detectados."
local helperState="Esperando..."
local function clearItems()
    for _,child in ipairs(feedArea:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end
local function section(text)
    local f=el("Frame",feedArea,{Size=UDim2.new(1,-8,0,22),BackgroundTransparency=1})
    label(f,text,11,{Size=UDim2.new(1,0,1,0),TextColor3=C.purple,Font=Enum.Font.GothamBold})
end
local function bodyMessage(txt)
    local lines=1
    for _ in tostring(txt):gmatch("\n") do lines=lines+1 end
    local height=math.max(40,lines*15+12)
    local f=el("Frame",feedArea,{Size=UDim2.new(1,-8,0,height),BackgroundColor3=C.inset,BorderSizePixel=0})
    round(f,5)
    label(f,txt,10,{Position=UDim2.fromOffset(6,2),Size=UDim2.new(1,-12,1,-4),
        TextColor3=C.dim,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
end
local rarityColors={Cosmic=C.purple,Secret=Color3.fromRGB(255,103,139),
    Eternal=Color3.fromRGB(249,191,82),Divine=Color3.fromRGB(95,207,251)}
local function itemCard(it,prefix)
    local p=it.pred or {}
    local f=el("Frame",feedArea,{Size=UDim2.new(1,-8,0,79),BackgroundColor3=C.panel,BorderSizePixel=0})
    round(f,7);outline(f,C.edge,.5)
    local r=p.rarity or "SIN RAREZA"
    label(f,(prefix or "")..it.name,12,{Position=UDim2.fromOffset(7,4),Size=UDim2.new(1,-12,0,19),
        Font=Enum.Font.GothamBold,TextTruncate=Enum.TextTruncate.AtEnd})
    label(f,r.."  |  "..tostring(it.zone),10,{Position=UDim2.fromOffset(7,24),Size=UDim2.new(1,-12,0,14),
        TextTruncate=Enum.TextTruncate.AtEnd,TextColor3=rarityColors[r] or C.dim})
    local income=good(p.income) and ("$"..moneyFormat(p.income).."/s") or "Ingreso N/D"
    local mark=(p.method=="DIRECTO_REPLICADO") and "DIRECTO" or (good(p.income) and "ESTIMADO" or "SIN DATO")
    label(f,income.."  ["..mark.."]",10,{Position=UDim2.fromOffset(7,41),Size=UDim2.new(1,-12,0,15),
        TextColor3=(mark=="DIRECTO") and C.green or C.orange,TextTruncate=Enum.TextTruncate.AtEnd})
    local weight=good(p.weight) and string.format("%.1f kg",p.weight) or "masa N/D"
    label(f,weight.."  |  "..tostring(it.location).." | Job "..SESSION_JOB_ID:sub(1,8).."  |  "..tostring(it.uid),9,{Position=UDim2.fromOffset(7,58),Size=UDim2.new(1,-12,0,14),
        TextColor3=C.dim,TextTruncate=Enum.TextTruncate.AtEnd})
end
local function displayFeed()
    clearItems();feedArea.CanvasPosition=Vector2.new(0,0)
    if currentView=="STATS" then
        section("ESTADISTICAS - ULTIMO ESCANEO")
        bodyMessage(statsText)
        return
    elseif currentView=="LOGS" then
        section("LOGS DE DETECCION")
        bodyMessage(logsText)
        return
    end
    section("ESTADO DE ENVIO AL FINDER WEB")
    bodyMessage(uploadMessage.."\nEl LIVE FEED web muestra detecciones aceptadas; esta lista es del servidor actual.")
    section("TOP 5 - INGRESO DISPONIBLE")
    if #feedItems.top==0 then
        bodyMessage("No hay objetivos con ingreso calculable.")
    else
        for i,it in ipairs(feedItems.top) do itemCard(it,tostring(i)..". ") end
    end
    for _,r in ipairs({"Secret","Eternal","Divine","Cosmic"}) do
        local g=feedItems.grouped and feedItems.grouped[r] or {}
        section(string.upper(r).."  ("..#g.." presentes)")
        if #g==0 then bodyMessage("Ninguno identificado con esta rareza.")
        else for _,it in ipairs(g) do itemCard(it) end end
    end
    section("SIN RAREZA CONFIRMADA")
    bodyMessage(tostring(feedItems.pending or 0).." huevos pendientes. Revisar COPIAR TODO; pueden incluir rarezas de interes.")
end
local function switchView(v)
    currentView=v
    logTab.BackgroundColor3=v=="LOGS" and Color3.fromRGB(49,45,100) or C.panel
    statsTab.BackgroundColor3=v=="STATS" and Color3.fromRGB(49,45,100) or C.panel
    feedTab.TextColor3=v=="FEED" and C.fg or C.dim
    displayFeed()
end
logTab.MouseButton1Click:Connect(function()switchView("LOGS")end)
statsTab.MouseButton1Click:Connect(function()switchView("STATS")end)
feedTab.MouseButton1Click:Connect(function()switchView("FEED")end)
cmdTab.MouseButton1Click:Connect(function()
    console.Visible=not console.Visible
    cmdTab.BackgroundColor3=console.Visible and Color3.fromRGB(49,45,100) or C.panel
end)
cmdTab.BackgroundColor3=Color3.fromRGB(49,45,100)
local function show(n)
    pageNum=n
    local str=pages[n] or ""
    local visible=str
    if #visible>80000 then visible=visible:sub(1,80000).."\n...REPORTE RECORTADO EN PANTALLA; COPIAR TODO CONSERVA EL COMPLETO." end
    output.Text=visible
    local charsPerLine=34
    local lines=0
    for line in (visible.."\n"):gmatch("([^\n]*)\n") do
        lines=lines+math.max(1,math.ceil(#line/charsPerLine))
    end
    local height=math.max(220,lines*14+20)
    output.Size=UDim2.new(1,-14,0,height)
    consoleArea.CanvasSize=UDim2.new(0,0,0,height+10)
    consoleArea.CanvasPosition=Vector2.new(0,0)
    cmdTitle.Text="COMANDS DE PRUEBA  ["..n.."/2]  TOCA"
end
consoleHead.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
        show(3-pageNum)
    end
end)
-- Arrastrar desde el titulo del panel principal y el borde de la consola.
local mainDrags=movable(top,main)
local consoleDrags=movable(cmdTitle,console)
local function refreshFeed(ranked,grouped,unresolved,scanned,newTargets)
    feedItems={top={},grouped=grouped,pending=#unresolved}
    for i=1,math.min(5,#ranked) do feedItems.top[i]=ranked[i] end
    local counts={}
    for _,r in ipairs(RARITIES) do counts[#counts+1]=r.."="..#grouped[r] end
    statsText="Huevos visibles: "..scanned.."\n"..table.concat(counts,"\n")..
        "\nSin rareza: "..#unresolved.."\nTOP con ingreso: "..#ranked..
        "\nServidor: PlaceId="..tostring(SESSION_PLACE_ID).." | JobId="..SESSION_JOB_ID..
        "\n"..uploadMessage.."\nDatos en este cliente, no en otros servidores."
    local notices={"Ultimo escaneo: "..tostring(scanned).." huevos vistos",statsText,"JOIN: "..joinLink()}
    if #newTargets>0 then
        notices[#notices+1]="NUEVOS:"
        for _,v in ipairs(newTargets) do notices[#notices+1]=v end
    end
    logsText=table.concat(notices,"\n")
    cap.Text="SESION ACTUAL | "..scanned
    feedState.Text="S:"..#grouped.Secret.." E:"..#grouped.Eternal.." D:"..#grouped.Divine
    displayFeed()
end

local connections={}
local live=true
local busy=false
local pending=false
local lastScan=0
local previousIds=nil
-- Registro de identidad por INSTANCIA, estable mientras el objeto siga replicado.
-- Dos huevos con mismo nombre, UID o GetFullName no se combinan.
local objectIds=setmetatable({}, {__mode="k"})
local objectSequence=0
local function instanceKey(o)
    local existing=objectIds[o]
    if existing then return existing end
    objectSequence=objectSequence+1
    local key=string.format("OBJ-%05d",objectSequence)
    objectIds[o]=key
    return key
end
-- El backend existente usa POST /api/collect/batch con Bearer del recolector.
-- Usamos el transportador HTTP disponible en Delta. No se invocan remotos del juego.
local function getHttpRequest()
    if type(request)=="function" then return request end
    if type(http_request)=="function" then return http_request end
    if type(ENV.request)=="function" then return ENV.request end
    if type(ENV.http_request)=="function" then return ENV.http_request end
    if type(syn)=="table" and type(syn.request)=="function" then return syn.request end
    if type(http)=="table" and type(http.request)=="function" then return http.request end
    return nil
end
local function eggExternalId(it)
    -- Clave ESTABLE cuando hay UID o ruta individual; no unir por nombre.
    -- En Halloween las rutas se repiten: se usa UID y/o posicion XYZ.
    local native=it.nativeUid and tostring(it.nativeUid) or ""
    local xyz=tostring(it.coords or it.location or "N/D")
    if native~="" and native~="nil" then
        return ("UID:"..native.."|"..xyz):sub(1,155)
    end
    if it.path and it.path:match("[%x]+$") and not it.path:find("HalloweenEgg",1,true) then
        return ("PATH:"..it.path):sub(-155)
    end
    -- Ultimo recurso: mismo objeto conserva it.uid durante la sesion.
    -- Si otro huevo aparece en exactamente el mismo lugar, el sufijo lo distingue.
    return ("POS:"..tostring(it.zone)..":"..tostring(it.name)..":"..xyz..":"..tostring(it.uid)):sub(1,155)
end
local function apiItems(all)
    local items={}
    local usedIds={}
    for _,it in ipairs(all) do
        -- No enviar Prehistoric. La API almacena los no clasificados solo para diagnostico privado.
        if it.zone~="Prehistoric" then
            local p=it.pred or {}
            local kind="DESCONOCIDO"
            if good(p.income) then
                kind=p.method=="DIRECTO_REPLICADO" and "DIRECTO" or "ESTIMADO"
            end
            local external=eggExternalId(it)
            -- Si dos ejemplares comparten incluso UID y coordenadas, NO fusionarlos.
            if usedIds[external] then
                external=(external:sub(1,136).."|dup:"..tostring(it.uid)):sub(1,155)
            end
            usedIds[external]=true
            local obj={
                place_id=SESSION_PLACE_ID,server_id=SESSION_JOB_ID,
                egg_id=external,egg_name=it.name,rarity=p.rarity,
                biome=it.zone,income_per_second=good(p.income) and p.income or nil,
                income_type=kind,weight_kg=good(p.weight) and p.weight or nil,
                mutation=type(p.mutation)=="string" and p.mutation or nil,
                multiplier=good(p.mult) and p.mult or nil
            }
            items[#items+1]=obj
        end
    end
    return items
end
local function uploadToFeed(all,newTargets)
    if not sendingEnabled or uploadBusy then return end
    if SESSION_JOB_ID=="" or not SESSION_PLACE_ID or SESSION_PLACE_ID<=0 then
        uploadMessage="API: SIN PLACEID/JOBID (no se envio)";return
    end
    local send=getHttpRequest()
    if not send then
        uploadMessage="API: NO HAY HTTP REQUEST EN ESTE EJECUTOR";return
    end
    local items=apiItems(all)
    if #items==0 then uploadMessage="API: SIN HUEVOS PARA ENVIAR";return end
    local stamp=os.clock()
    -- Backend: limite de envios por credencial de 90 s.
    -- Multiples bots con una key aun pueden recibir 429.
    if stamp-lastUploadClock<95 then return end
    lastUploadClock=stamp
    uploadBusy=true
    task.spawn(function()
        local accepted,ignored=0,0
        local errorText=nil
        for start=1,#items,75 do
            if not live then break end
            local batch={}
            for i=start,math.min(start+74,#items) do batch[#batch+1]=items[i] end
            local okBody,body=pcall(function()return HttpService:JSONEncode({items=batch})end)
            if not okBody then errorText="Error JSON";break end
            local ok,res=pcall(send,{Url=apiUrl,Method="POST",Headers={
                ["Content-Type"]="application/json",
                ["Authorization"]="Bearer "..collectorToken
            },Body=body})
            if not ok or type(res)~="table" then
                errorText="HTTP sin respuesta";break
            end
            local code=tonumber(res.StatusCode or res.Status or res.status_code or 0) or 0
            if code<200 or code>=300 then
                local hint=code==429 and "limite de la key compartida" or
                    (code==401 and "key invalida" or
                    (code==404 and "ruta API incorrecta" or "revisa la conexion"))
                errorText="HTTP "..tostring(code).." ("..hint..")";break
            end
            local okData,parsed=pcall(function()return HttpService:JSONDecode(res.Body or "{}")end)
            if okData and type(parsed)=="table" then
                accepted=accepted+(tonumber(parsed.accepted) or #batch)
                ignored=ignored+(tonumber(parsed.ignored) or 0)
            else accepted=accepted+#batch end
        end
        if live then
            uploadMessage=errorText and ("API: ERROR "..errorText) or
                ("API: ENVIO OK ("..accepted.." huevos; "..ignored.." omitidos)")
            status.Text=uploadMessage
            if currentView=="FEED" then displayFeed() end
        end
        uploadBusy=false
    end)
end
local function render()
    if busy or not live then pending=true;return end
    busy=true;pending=false
    scanBtn.Text="ESCANEANDO..."
    local ok,err=pcall(function()
        if not initialized then setupCatalog() end
        local anchor=anchorList()
        local all,seen,scanned,excluded={},{},0,0
        local rootDetails={}
        for _,entry in ipairs(ROOTS) do
            local root=path(entry[1]);local count=0
            if root then
                for _,o in ipairs(root:GetChildren()) do
                    if o:IsA("Model") or o:IsA("BasePart") then
                        count=count+1
                        local nativeUid=getField(o,{"HalloweenEggUid","EggUid","UID","Uid"})
                        local key=instanceKey(o)
                        -- Solo omitir la MISMA instancia visitada dos veces, nunca otro huevo
                        -- con nombre, ruta o UID iguales.
                        if not seen[o] then
                            seen[o]=true
                            local owner=getField(o,{"OwnerUserId"})
                            if owner~=nil then excluded=excluded+1
                            else
                                scanned=scanned+1
                                local name,ident=identify(o)
                                if name then
                                    local zone=getZone(o,entry[2],anchor)
                                    local p=extract(o,name,zone)
                                    local point=pos(o)
                                    local info={name=name,ident=ident,zone=zone,uid=key,nativeUid=nativeUid,
                                        location=point and string.format("X%.0f Z%.0f",point.X,point.Z) or "N/D",
                                        path=safeFull(o),coords=point and string.format("%.2f,%.2f,%.2f",point.X,point.Y,point.Z) or "N/D",pred=p}
                                    all[#all+1]=info
                                else
                                    -- Un nombre oculto no impide comprobar atributos de rareza.
                                    local zone=getZone(o,entry[2],anchor)
                                    local p=extract(o,"???",zone)
                                    local point=pos(o)
                                    all[#all+1]={name="???",ident=ident,zone=zone,
                                        uid=key,nativeUid=nativeUid,location=point and string.format("X%.0f Z%.0f",point.X,point.Z) or "N/D",
                                        path=safeFull(o),coords=point and string.format("%.2f,%.2f,%.2f",point.X,point.Y,point.Z) or "N/D",pred=p}
                                end
                            end
                        end
                    end
                end
            end
            rootDetails[#rootDetails+1]=entry[1].."="..count
        end
        local ranked,unknown,undecided,conflicts={},{},{},{}
        local grouped={Cosmic={},Secret={},Eternal={},Divine={}}
        local unresolved={}
        for _,it in ipairs(all) do
            local p=it.pred
            if p.conflict then conflicts[#conflicts+1]=it end
            if p.rarity and TARGET[p.rarity] then
                grouped[p.rarity][#grouped[p.rarity]+1]=it
                if good(p.income) then ranked[#ranked+1]=it
                else undecided[#undecided+1]=it end
            else
                unresolved[#unresolved+1]=it
                if it.name~="???" then
                    local bi=BASE[norm(it.name)] or EXTRA[norm(it.name)]
                    if bi and good(bi.income) then unknown[#unknown+1]=it end
                end
            end
        end
        local function byIncome(a,b)
            local aa=a.pred and a.pred.income
            local bb=b.pred and b.pred.income
            if good(aa)~=good(bb) then return good(aa) end
            if good(aa) and good(bb) and aa~=bb then return aa>bb end
            if a.name~=b.name then return a.name<b.name end
            return a.uid<b.uid
        end
        table.sort(ranked,byIncome)
        for _,r in ipairs(RARITIES) do table.sort(grouped[r],byIncome) end
        table.sort(unknown,function(a,b)
            local aa=BASE[norm(a.name)] or EXTRA[norm(a.name)]
            local bb=BASE[norm(b.name)] or EXTRA[norm(b.name)]
            return aa.income>bb.income
        end)
        local nowIds={}
        local newTargets={}
        for _,r in ipairs(RARITIES) do
            for _,it in ipairs(grouped[r]) do
                local unique=tostring(it.uid)
                nowIds[unique]=true
                if previousIds and not previousIds[unique] then
                    newTargets[#newTargets+1]=r..": "..it.name.." | "..it.zone
                end
            end
        end
        previousIds=nowIds
        local a={
            "=== PVFINDER V36.2 | TOP + JOIN SERVIDOR + API LIVE FEED ===",
            "SERVIDOR ACTUAL (obtenido del cliente, NO inferido)",
            "PlaceId: "..tostring(SESSION_PLACE_ID or "N/D"),
            "JobId: "..(SESSION_JOB_ID~="" and SESSION_JOB_ID or "N/D"),
            "JOIN: "..joinLink(),
            "Estado del envio: "..uploadMessage,
            "COSMIC / SECRET / ETERNAL / DIVINE",
            "Solo datos replicados en este cliente; no ve objetos ocultos.",
            "Ingreso por segundo DIRECTO si esta disponible; si no, ESTIMADO.",
            "IMPORTANTE: un Secret sin ingreso SI aparece en la lista Secret.",
            "Cada huevo es un ejemplar independiente aunque repita nombre o UID.",
            ""
        }
        local function detail(it,i)
            local p=it.pred
            local pieces={
                tostring(i)..". "..it.name.." | "..tostring(p.rarity),
                "  Ingreso: $"..moneyFormat(p.income).."/s | "..tostring(p.method or "SIN_INGRESO"),
                "  Bioma: "..it.zone.." | "..it.location,
                "  Masa: "..(good(p.weight) and string.format("%.2f kg",p.weight) or "N/D")..
                    " ("..tostring(p.weightSource or "SIN_DATO")..")",
                "  Base: $"..moneyFormat(p.baseIncome).."/s | "..tostring(p.baseIncomeSource or "SIN_BASE"),
                "  Escala: "..(good(p.scale) and string.format("%.3fx",p.scale) or "N/D")..
                    " | Mutacion: "..tostring(p.mutation or "NO_REPLICADA"),
                "  Rareza: "..tostring(p.source)..(p.conflict and " | CONFLICTO" or ""),
                "  Fuentes: "..tostring(p.known or "N/D"),
                "  Ejemplar: "..tostring(it.uid).." | UID juego: "..tostring(it.nativeUid or "N/D"),
                "  Egg ID API: "..eggExternalId(it),
                "  PlaceId/JobId: "..tostring(SESSION_PLACE_ID).." / "..SESSION_JOB_ID,
            }
            return table.concat(pieces,"\n")
        end
        if #newTargets>0 then
            a[#a+1]="=== NUEVOS OBJETIVOS DESDE EL ESCANEO ANTERIOR ==="
            for _,msg in ipairs(newTargets) do a[#a+1]=msg end
            a[#a+1]=""
        end
        a[#a+1]="=== TOP 5 POR INGRESO (SOLO 4 RAREZAS) ==="
        for i=1,math.min(5,#ranked) do a[#a+1]=detail(ranked[i],i);a[#a+1]="" end
        if #ranked<5 then a[#a+1]="SOLO "..#ranked.."/5 con ingreso calculable: no se inventan puestos." end
        a[#a+1]=""
        a[#a+1]="=== LISTAS DE HUEVOS PRESENTES POR RAREZA ==="
        for _,r in ipairs(RARITIES) do
            local group=grouped[r]
            a[#a+1]=""
            a[#a+1]="=== "..string.upper(r).." | "..#group.." DETECTADOS ==="
            if #group==0 then
                a[#a+1]="No se identificaron con esta rareza en el cliente."
                a[#a+1]="ATENCION: los SIN_RAREZA estan en pagina 2 y pueden incluir "..r.."."
            else
                for i,it in ipairs(group) do
                    local d=it.pred
                    local v=good(d.income) and ("$"..moneyFormat(d.income).."/s") or "INGRESO N/D"
                    a[#a+1]=i..". "..it.name.." | "..v.." | "..it.zone..
                        " | "..it.location.." | "..d.source..(d.conflict and " | CONFLICTO" or "")
                    a[#a+1]="   Masa: "..(good(d.weight) and string.format("%.2f kg",d.weight) or "N/D")..
                        " | Ejemplar: "..tostring(it.uid).." | UID: "..tostring(it.nativeUid or "N/D")
                end
            end
        end
        a[#a+1]=""
        a[#a+1]="=== RESUMEN ==="
        a[#a+1]="Detectados="..scanned.." | Cosmic="..#grouped.Cosmic..
            " Secret="..#grouped.Secret.." Eternal="..#grouped.Eternal.." Divine="..#grouped.Divine
        a[#a+1]="Objetivos con ingreso="..#ranked.." | sin ingreso="..#undecided..
            " | sin rareza="..#unresolved
        a[#a+1]="Si viste un Secret y figura en SIN RAREZA, el cliente no entrego su rareza o nombre con certeza."
        a[#a+1]="El calculo con masa/escala es estimacion; sin mutacion replicada NO es ingreso real."

        local b={"=== DETALLE DEL ESCANEO COMPLETO ===",
            "PlaceId="..tostring(SESSION_PLACE_ID).." | JobId="..SESSION_JOB_ID,
            "JOIN="..joinLink(),
            table.concat(rootDetails," | "),"Catalogo="..#catalog,""}
        b[#b+1]="=== OBJETIVOS SIN INGRESOS (PERO CON RAREZA) ==="
        for _,it in ipairs(undecided) do
            b[#b+1]=it.name.." | "..it.zone.." | "..tostring(it.pred.rarity).." | "..it.location..
                " | "..tostring(it.pred.source)
        end
        b[#b+1]="=== NO CLASIFICADOS: REVISAR SI HAY SECRET/ETERNAL/DIVINE ==="
        for _,it in ipairs(unresolved) do
            b[#b+1]=it.name.." | "..it.zone.." | "..it.location.." | "..it.ident..
                " | "..it.path.." | "..tostring(it.pred.known or "SIN_RAREZA")..
                " | Ejemplar: "..tostring(it.uid).." | UID: "..tostring(it.nativeUid or "N/D")
        end
        b[#b+1]="=== INGRESOS BASE HISTORICOS, RAREZA NO DEMOSTRADA ==="
        for i=1,math.min(30,#unknown) do
            local it=unknown[i]
            local bi=BASE[norm(it.name)] or EXTRA[norm(it.name)]
            b[#b+1]=it.name.." | "..it.zone.." | "..bi.src.." $"..moneyFormat(bi.income).."/s BASE"
        end
        b[#b+1]="=== CONFLICTOS ENTRE FUENTES DE RAREZA ==="
        for _,it in ipairs(conflicts) do
            b[#b+1]=it.name.." | "..it.zone.." | "..tostring(it.pred.known or "SIN_DETALLE")
        end
        b[#b+1]="=== TODOS LOS EJEMPLARES VISIBLES ==="
        for _,it in ipairs(all) do
            b[#b+1]=it.name.." | "..it.zone.." | "..tostring(it.pred.rarity or "RAR_N/D")..
                " | "..it.ident.." | "..it.path.." | Ejemplar: "..tostring(it.uid)..
                " | UID: "..tostring(it.nativeUid or "N/D")
        end
        refreshFeed(ranked,grouped,unresolved,scanned,newTargets)
        uploadToFeed(all,newTargets) -- Peticion HTTP ASINCRONA (no bloquea el panel)
        pages[1]=table.concat(a,"\n");pages[2]=table.concat(b,"\n")
        full=pages[1].."\n\n"..pages[2]
        show(pageNum)
        lastScan=os.clock()
        status.Text="TOP "..math.min(5,#ranked).."/5 | S:"..#grouped.Secret..
            " E:"..#grouped.Eternal.." D:"..#grouped.Divine..
            " | nuevos:"..#newTargets.." | "..scanned.." huevos"
    end)
    if not ok then
        pages[1]="ERROR V36.1: "..tostring(err)
        show(1);status.Text="ERROR: "..tostring(err):sub(1,75)
    end
    busy=false;scanBtn.Text="ESCANEAR"
    if pending and live then pending=false;task.delay(.5,function()if live then render()end end) end
end
local function request()
    if not live then return end
    if busy then pending=true;return end
    if os.clock()-lastScan<.6 then return end
    task.defer(render)
end
triggerAfterSave=function()
    lastUploadClock=-math.huge
    request()
end
scanBtn.MouseButton1Click:Connect(request)
copyBtn.MouseButton1Click:Connect(function()
    if full=="" then status.Text="Primero ESCANEAR";return end
    local f=setclipboard or toclipboard or (syn and syn.write_clipboard)
    if type(f)=="function" then
        local ok=pcall(f,full)
        status.Text=ok and ("Copiado "..#full.." caracteres") or "Error portapapeles"
        feedState.Text=ok and "COPIADO" or "ERROR COPIAR"
    else
        status.Text="No hay portapapeles; selecciona el texto manualmente"
        feedState.Text="COPIA MANUAL"
    end
end)
local function listen()
    for _,e in ipairs(ROOTS) do
        local root=path(e[1])
        if root then
            connections[#connections+1]=root.ChildAdded:Connect(function()task.delay(.3,request)end)
            connections[#connections+1]=root.ChildRemoved:Connect(function()task.delay(.3,request)end)
        end
    end
end
ENV.__PVF_V362_STOP=function()
    live=false
    for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
    for _,c in ipairs(mainDrags) do pcall(function()c:Disconnect()end) end
    for _,c in ipairs(consoleDrags) do pcall(function()c:Disconnect()end) end
    pcall(function()gui:Destroy()end)
end
listen()
show(1)
task.spawn(function()
    render()
    while live and gui.Parent do
        task.wait(5)
        if live then render() end
    end
end)
