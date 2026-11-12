-- PVFinder Delta V3.1 — UI reconstruida. Visor de solo lectura.
-- Panel y controles se crean ANTES de leer la API.
-- Token viewer individual; nunca se usan credenciales de administrador.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local TeleportService=game:GetService("TeleportService")
local player=Players.LocalPlayer
local API="https://pvfinder.onrender.com"
local requestFn=request or http_request or (syn and syn.request) or (http and http.request)

local pg=player:WaitForChild("PlayerGui")
local uiParent=pg
if type(gethui)=="function" then
    local ok,root=pcall(gethui)
    if ok and typeof(root)=="Instance" then uiParent=root end
end
-- Eliminar copias antiguas en ambos lugares (iPhone puede cambiar gethui).
for _,root in ipairs({pg,uiParent}) do
    local previous=root:FindFirstChild("PVFinderViewer")
    if previous then previous:Destroy() end
end

local C={
    bg=Color3.fromRGB(10,15,34), card=Color3.fromRGB(22,29,57),
    purple=Color3.fromRGB(169,116,255), blue=Color3.fromRGB(65,154,255),
    outline=Color3.fromRGB(117,86,194),
    text=Color3.fromRGB(241,243,255), muted=Color3.fromRGB(164,176,207),
    green=Color3.fromRGB(98,242,172), red=Color3.fromRGB(255,140,156)
}
local screen=Instance.new("ScreenGui")
screen.Name="PVFinderViewer"
screen.ResetOnSpawn=false
screen.IgnoreGuiInset=true
screen.DisplayOrder=10000
screen.Parent=uiParent
local function corner(parent,pixels)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,pixels or 12)
    c.Parent=parent
end
local function stroke(parent,color)
    local s=Instance.new("UIStroke")
    s.Color=color or C.outline
    s.Thickness=1.5
    s.Parent=parent
end
local function text(parent,value,position,dimension,size,color,isBold)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.Text=tostring(value)
    l.TextColor3=color or C.text
    l.Font=isBold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize=size or 13
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.TextTruncate=Enum.TextTruncate.AtEnd
    l.Position=position
    l.Size=dimension
    l.Parent=parent
    return l
end
local function button(parent,value,position,dimension)
    local b=Instance.new("TextButton")
    b.Text=tostring(value)
    b.TextColor3=C.text
    b.Font=Enum.Font.GothamBold
    b.TextSize=13
    b.BackgroundColor3=C.card
    b.AutoButtonColor=true
    b.Position=position
    b.Size=dimension
    b.Parent=parent
    corner(b,10)
    stroke(b)
    return b
end
-- PVFinder V4: panel vertical a la derecha con CUADROS independientes.
-- El acceso aparece sobre el LIVE FEED, no ocupa los tres cuadros.
local function dims()
    local cam=workspace.CurrentCamera
    local v=cam and cam.ViewportSize or Vector2.new(1152,512)
    if v.X>v.Y then
        local width
        if v.X<1100 then
            width=math.clamp(v.X*.58,450,600)
        else
            width=math.clamp(v.X*.43,540,660)
        end
        return math.floor(math.min(width,v.X-12)),
               math.floor(math.clamp(v.Y*.87,310,640))
    end
    return math.floor(math.max(300,math.min(v.X-16,480))),
           math.floor(math.max(340,math.min(v.Y-45,670)))
end
local W,H=dims()
local HEADER_H=math.floor(math.clamp(H*.12,54,70))

local panel=Instance.new("Frame")
panel.Name="PV_Derecha"
panel.AnchorPoint=Vector2.new(1,.5)
panel.Position=UDim2.new(1,-12,.52,0)
panel.Size=UDim2.fromOffset(W,H)
panel.BackgroundColor3=C.bg
panel.BorderSizePixel=0
panel.Parent=screen
corner(panel,20)
stroke(panel,C.purple)
panel.ClipsDescendants=false

local header=Instance.new("Frame")
header.Name="PV_Encabezado"
header.Size=UDim2.new(1,0,0,HEADER_H)
header.BackgroundColor3=C.card
header.BorderSizePixel=0
header.Parent=panel
corner(header,18)
local headerGradient=Instance.new("UIGradient")
headerGradient.Color=ColorSequence.new(C.card,Color3.fromRGB(18,18,45))
headerGradient.Rotation=15
headerGradient.Parent=header
text(header,"PVFinder  V4",UDim2.fromOffset(14,8),
    UDim2.new(1,-98,0,27),21,C.text,true)
text(header,"LIVE FEED  •  SOLO LECTURA",UDim2.fromOffset(14,33),
    UDim2.new(1,-34,0,19),11,C.purple,true)
local closeButton=button(header,"HIDE",
    UDim2.new(1,-79,0,11),UDim2.fromOffset(67,32))
closeButton.Name="PV_Hide"

-- Área debajo del encabezado: columna de tres cuadros y LIVE FEED.
local body=Instance.new("Frame")
body.Name="PV_CuadrosIzquierda"
body.BackgroundTransparency=1
body.Position=UDim2.fromOffset(12,HEADER_H+9)
body.Size=UDim2.new(.315,-9,1,-(HEADER_H+18))
body.Parent=panel
body.ClipsDescendants=false

local feedPane=Instance.new("Frame")
feedPane.Name="PV_ListaDerecha"
feedPane.BackgroundColor3=Color3.fromRGB(11,18,40)
feedPane.BorderSizePixel=0
feedPane.Position=UDim2.new(.315,12,0,HEADER_H+9)
feedPane.Size=UDim2.new(.685,-24,1,-(HEADER_H+18))
feedPane.Parent=panel
corner(feedPane,13)
stroke(feedPane)

local function card(name,position)
    local frame=Instance.new("Frame")
    frame.Name=name
    frame.BackgroundColor3=C.card
    frame.BorderSizePixel=0
    frame.Position=position
    frame.Size=UDim2.new(1,0,1/3,-6)
    frame.Parent=body
    frame.ClipsDescendants=false
    corner(frame,12)
    stroke(frame,C.purple)
    local gradient=Instance.new("UIGradient")
    gradient.Color=ColorSequence.new(
        Color3.fromRGB(22,26,58),Color3.fromRGB(12,17,38))
    gradient.Rotation=80
    gradient.Parent=frame
    return frame
end
local autoCard=card("PV_Cuadro_AutoJoin",UDim2.new(0,0,0,0))
local moneyCard=card("PV_Cuadro_Dinero",UDim2.new(0,0,1/3,1))
local hideCard=card("PV_Cuadro_Hide",UDim2.new(0,0,2/3,2))

local autoIcon=text(autoCard,"🔗",UDim2.new(0,10,.12,0),
    UDim2.new(1,-20,0,24),20,C.purple,true)
local autoTitle=text(autoCard,"Auto join",UDim2.new(0,10,.41,-3),
    UDim2.new(1,-20,0,22),14,C.text,true)
local auto=button(autoCard,"OFF",
    UDim2.new(0,8,.70,0),UDim2.new(1,-16,0,29))
auto.AnchorPoint=Vector2.new(0,1)
auto.Name="PV_AutoJoin"
auto.TextSize=12

local moneyIcon=text(moneyCard,"💰",UDim2.new(0,10,.12,0),
    UDim2.new(1,-20,0,24),20,C.purple,true)
local moneyTitle=text(moneyCard,"Filtro de dinero",UDim2.new(0,9,.41,-4),
    UDim2.new(1,-14,0,20),12,C.text,true)
local filter=Instance.new("TextBox")
filter.Name="PV_Minimo"
filter.Text="100M o más"
filter.PlaceholderText="100M / 2B / 500B"
filter.PlaceholderColor3=C.muted
filter.ClearTextOnFocus=false
filter.Font=Enum.Font.GothamBold
filter.TextSize=12
filter.TextScaled=true
filter.TextColor3=C.text
filter.BackgroundColor3=Color3.fromRGB(27,24,62)
filter.TextXAlignment=Enum.TextXAlignment.Center
filter.AnchorPoint=Vector2.new(0,1)
filter.Position=UDim2.new(0,7,.92,0)
filter.Size=UDim2.new(1,-42,0,29)
filter.Parent=moneyCard
corner(filter,9)
stroke(filter,C.purple)
local choose=button(moneyCard,"▼",
    UDim2.new(1,-33,.92,-29),UDim2.fromOffset(27,29))
choose.TextSize=11

local hideIcon=text(hideCard,"◉",UDim2.new(0,10,.12,0),
    UDim2.new(1,-20,0,24),20,C.purple,true)
local hideTitle=text(hideCard,"Minimizar panel",UDim2.new(0,9,.41,-4),
    UDim2.new(1,-14,0,20),12,C.text,true)
local hideBottom=button(hideCard,"Hide",
    UDim2.new(0,8,.70,0),UDim2.new(1,-16,0,29))
hideBottom.AnchorPoint=Vector2.new(0,1)
hideBottom.Name="PV_HideInferior"

local liveText=text(feedPane,"LIVE FEED  •  0 HUEVOS",
    UDim2.fromOffset(10,9),UDim2.new(1,-20,0,20),11,C.purple,true)

local list=Instance.new("ScrollingFrame")
list.Name="PV_Resultados"
list.BackgroundTransparency=1
list.BorderSizePixel=0
list.Position=UDim2.fromOffset(8,34)
list.Size=UDim2.new(1,-16,1,-74)
list.CanvasSize=UDim2.fromOffset(0,0)
list.ScrollBarThickness=3
list.ScrollBarImageColor3=C.purple
list.Visible=false
list.Parent=feedPane
local layout=Instance.new("UIListLayout")
layout.SortOrder=Enum.SortOrder.LayoutOrder
layout.Padding=UDim.new(0,6)
layout.Parent=list
local function updateCanvas()
    list.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+8)
end
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

local status=text(feedPane,"Ingresa un token de jugador",
    UDim2.new(0,9,1,-34),UDim2.new(1,-18,0,26),10,C.muted)

-- Login sólo en la columna de resultados. No es acceso administrador.
local access=Instance.new("Frame")
access.Name="PV_LoginViewer"
access.BackgroundColor3=C.bg
access.Position=UDim2.fromOffset(8,42)
access.Size=UDim2.new(1,-16,0,155)
access.Parent=feedPane
access.ZIndex=12
corner(access,10)
stroke(access,C.outline)
local loginTitle=text(access,"TOKEN DE JUGADOR",
    UDim2.fromOffset(9,9),UDim2.new(1,-18,0,21),12,C.purple,true)
loginTitle.ZIndex=13
local entry=Instance.new("TextBox")
entry.Name="PV_Token"
entry.PlaceholderText="Token / enlace privado"
entry.PlaceholderColor3=C.muted
entry.Text=""
entry.ClearTextOnFocus=false
entry.Font=Enum.Font.Gotham
entry.TextSize=11
entry.TextColor3=C.text
entry.BackgroundColor3=C.card
entry.Position=UDim2.fromOffset(8,37)
entry.Size=UDim2.new(1,-16,0,31)
entry.ZIndex=13
entry.Parent=access
corner(entry,8)
stroke(entry)
local enter=button(access,"ENTRAR",
    UDim2.fromOffset(8,76),UDim2.new(1,-16,0,32))
enter.ZIndex=13
local accessInfo=text(access,"Pega el enlace creado en PVFinder Admin.",
    UDim2.fromOffset(8,114),UDim2.new(1,-16,0,33),10,C.muted)
accessInfo.TextWrapped=true
accessInfo.ZIndex=13

-- Burbuja PV, visible al pulsar HIDE.
local bubble=button(screen,"PV",UDim2.new(1,-77,.36,0),UDim2.fromOffset(57,57))
bubble.Name="PV_Burbuja"
bubble.TextSize=18
bubble.BackgroundColor3=C.purple
bubble.Visible=false
corner(bubble,30)
stroke(bubble,C.blue)

-- Colocar controles DENTRO de cada cuadro incluso en iPhone horizontal pequeño.
local function arrangeCards()
    local h=(H-HEADER_H-18)/3-6
    local compact=h<110
    for _,pair in ipairs({
        {autoIcon,autoTitle,auto},
        {moneyIcon,moneyTitle,filter},
        {hideIcon,hideTitle,hideBottom}
    }) do
        local icon,title,action=pair[1],pair[2],pair[3]
        if compact then
            icon.Position=UDim2.fromOffset(8,5)
            icon.Size=UDim2.fromOffset(27,21)
            title.Position=UDim2.fromOffset(32,7)
            title.Size=UDim2.new(1,-34,0,20)
        else
            icon.Position=UDim2.new(0,10,.14,0)
            icon.Size=UDim2.new(1,-20,0,26)
            title.Position=UDim2.new(0,10,.45,0)
            title.Size=UDim2.new(1,-20,0,21)
        end
    end
    if compact then
        auto.Position=UDim2.new(0,8,1,-34)
        hideBottom.Position=UDim2.new(0,8,1,-34)
        filter.Position=UDim2.new(0,7,1,-34)
        choose.Position=UDim2.new(1,-33,1,-34)
    else
        auto.Position=UDim2.new(0,8,1,-42)
        hideBottom.Position=UDim2.new(0,8,1,-42)
        filter.Position=UDim2.new(0,7,1,-42)
        choose.Position=UDim2.new(1,-33,1,-42)
    end
    auto.AnchorPoint=Vector2.new(0,0)
    hideBottom.AnchorPoint=Vector2.new(0,0)
    filter.AnchorPoint=Vector2.new(0,0)
end
arrangeCards()

-- Escalado sin perder la estructura de dos columnas.
local cam=workspace.CurrentCamera
if cam then
    cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        if not screen.Parent then return end
        W,H=dims()
        HEADER_H=math.floor(math.clamp(H*.12,54,70))
        panel.Size=UDim2.fromOffset(W,H)
        panel.Position=UDim2.new(1,-12,.52,0)
        header.Size=UDim2.new(1,0,0,HEADER_H)
        body.Position=UDim2.fromOffset(12,HEADER_H+9)
        body.Size=UDim2.new(.315,-9,1,-(HEADER_H+18))
        feedPane.Position=UDim2.new(.315,12,0,HEADER_H+9)
        feedPane.Size=UDim2.new(.685,-24,1,-(HEADER_H+18))
        arrangeCards()
    end)
end
-- Minimizar + arrastrar bolita. Mantener boton HIDE independiente.
local dragging=false
local startInput,startPos,wasMoved,activeInput
bubble.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or
       input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        activeInput=input
        startInput=input.Position
        startPos=bubble.AbsolutePosition
        wasMoved=false
    end
end)
UIS.InputChanged:Connect(function(input)
    if not dragging or not startInput then return end
    if activeInput and activeInput.UserInputType==Enum.UserInputType.Touch then
        if input~=activeInput then return end
    elseif input.UserInputType~=Enum.UserInputType.MouseMovement then
        return
    end
    local diff=input.Position-startInput
    if diff.Magnitude>8 then wasMoved=true end
    if not wasMoved then return end
    local cam=workspace.CurrentCamera
    local extent=cam and cam.ViewportSize or Vector2.new(1152,512)
    bubble.Position=UDim2.fromOffset(
        math.clamp(startPos.X+diff.X,0,math.max(0,extent.X-57)),
        math.clamp(startPos.Y+diff.Y,0,math.max(0,extent.Y-57))
    )
end)
UIS.InputEnded:Connect(function(input)
    if input==activeInput then
        dragging=false
        activeInput=nil
    end
end)
local function hide()
    panel.Visible=false
    bubble.Visible=true
end
local function show()
    bubble.Visible=false
    panel.Visible=true
end
closeButton.MouseButton1Click:Connect(hide)
hideBottom.MouseButton1Click:Connect(hide)
bubble.MouseButton1Click:Connect(function()
    if not wasMoved then show() end
end)

-- Menú de mínimos abierto sobre la lista (sin tapar botones).
local thresholds={
    {0,"TODOS"},{1e8,"100M"},{2.5e8,"250M"},{5e8,"500M"},
    {1e9,"1B"},{2e9,"2B"},{5e9,"5B"},
    {1e10,"10B"},{5e10,"50B"},{1e11,"100B"},
    {2.5e11,"250B"},{5e11,"500B"}
}
local minIncome=1e8
local menu=Instance.new("ScrollingFrame")
menu.Name="PV_OpcionesDinero"
menu.BackgroundColor3=C.card
menu.Position=UDim2.new(0,0,1,-9)
menu.Size=UDim2.new(1,0,0,155)
menu.ScrollBarThickness=3
menu.ScrollBarImageColor3=C.purple
menu.CanvasSize=UDim2.fromOffset(0,#thresholds*34)
menu.BorderSizePixel=0
menu.ZIndex=40
menu.Visible=false
menu.Parent=moneyCard
corner(menu,10)
stroke(menu)
local viewerSession=nil
local eggs={}
local autoJoin=false
local armedAt=0
local known={}
local loginBusy=false
local function reportKey(x)
    -- Un latido del mismo huevo NO es un huevo nuevo: evitar Auto Join
    -- repetido por las actualizaciones periodicas del recolector.
    return tostring(x.server_id or "").."|"..tostring(x.egg_id or "")
end
local function parseMoney(value)
    local cleaned=tostring(value or ""):upper():gsub(",","")
    local n,suffix=cleaned:match("^%s*%$?%s*(%d+%.?%d*)%s*([KMBT]?)")
    n=tonumber(n)
    if not n then return nil end
    return n*(({K=1e3,M=1e6,B=1e9,T=1e12})[suffix] or 1)
end
local function formatMoney(value)
    local n=tonumber(value)
    if not n then return "N/D" end
    if n>=1e12 then return string.format("%.2fT",n/1e12) end
    if n>=1e9 then return string.format("%.2fB",n/1e9) end
    if n>=1e6 then return string.format("%.2fM",n/1e6) end
    return string.format("%.0f",n)
end
local function clearResults()
    for _,child in ipairs(list:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
    end
end
local function display()
    clearResults()
    local rows={}
    for _,x in ipairs(eggs) do
        local earn=tonumber(x.income_per_second)
        local job=tostring(x.server_id or "")
        if job~="" and (minIncome==0 or (earn and earn>=minIncome)) then
            rows[#rows+1]=x
        end
    end
    table.sort(rows,function(a,b)
        local x=tonumber(a.income_per_second) or -1
        local y=tonumber(b.income_per_second) or -1
        if x==y then return tostring(a.egg_id)<tostring(b.egg_id) end
        return x>y
    end)
    liveText.Text="LIVE FEED  •  "..tostring(#rows).." HUEVOS"
    if #rows==0 then
        text(list,viewerSession and "Sin huevos para este filtro." or
            "Accede con tu token para consultar.",UDim2.fromOffset(5,12),
            UDim2.new(1,-8,0,36),12,C.muted)
    end
    for i,x in ipairs(rows) do
        local card=Instance.new("Frame")
        card.Name="PV_Egg_"..tostring(i)
        card.Size=UDim2.new(1,-5,0,76)
        card.BackgroundColor3=C.card
        card.LayoutOrder=i
        card.Parent=list
        corner(card,10)
        stroke(card)
        text(card,tostring(x.egg_name or "Huevo"),
            UDim2.fromOffset(9,5),UDim2.new(1,-84,0,24),13,C.text,true)
        text(card,tostring(x.rarity or "?").."  •  "..tostring(x.biome or "?"),
            UDim2.fromOffset(9,28),UDim2.new(1,-82,0,20),10,C.muted)
        text(card,"$"..formatMoney(x.income_per_second).."/s",
            UDim2.fromOffset(9,50),UDim2.new(1,-88,0,21),12,C.green,true)
        local go=button(card,"JOIN",UDim2.new(1,-77,.5,-17),UDim2.fromOffset(70,34))
        go.MouseButton1Click:Connect(function()
            local place=tonumber(x.place_id)
            local job=tostring(x.server_id or "")
            if not place or #job~=36 then
                status.Text="Servidor sin datos JOIN"
                return
            end
            status.Text="Intentando JOIN a "..tostring(x.egg_name or "huevo")
            local ok,err=pcall(function()
                TeleportService:TeleportToPlaceInstance(place,job,player)
            end)
            if not ok then
                status.Text="Roblox bloqueó el JOIN"
                warn("[PVFinder] JOIN: "..tostring(err))
            end
        end)
    end
    updateCanvas()
end
for i,option in ipairs(thresholds) do
    local b=button(menu,option[2].." o más",
        UDim2.fromOffset(4,2+(i-1)*34),UDim2.new(1,-11,0,31))
    b.ZIndex=41
    b.MouseButton1Click:Connect(function()
        minIncome=option[1]
        filter.Text=option[1]==0 and "TODOS" or (option[2].." o más")
        menu.Visible=false
        status.Text="Filtro mínimo: "..option[2].."/s"
        display()
    end)
end
choose.MouseButton1Click:Connect(function()
    menu.Visible=not menu.Visible
end)
filter.FocusLost:Connect(function()
    local n=parseMoney(filter.Text)
    if n and n>=0 and n<=5e11 then
        minIncome=n
        filter.Text=n==0 and "TODOS" or (formatMoney(n).." o más")
        status.Text="Filtro mínimo actualizado"
        display()
    else
        filter.Text=minIncome==0 and "TODOS" or (formatMoney(minIncome).." o más")
        status.Text="Usa un valor entre 100M y 500B"
    end
    menu.Visible=false
end)

local function join(row)
    if not row then return false end
    local place=tonumber(row.place_id)
    local job=tostring(row.server_id or "")
    if not place or #job~=36 or not job:match("^[%x%-]+$") then return false end
    if place==game.PlaceId and job==game.JobId then return false end
    status.Text="Entrando al servidor de "..tostring(row.egg_name or "huevo")
    local ok=pcall(function()
        TeleportService:TeleportToPlaceInstance(place,job,player)
    end)
    return ok
end
local function refreshToggle()
    auto.Text=autoJoin and "ON ✓" or "OFF"
    auto.BackgroundColor3=autoJoin and C.purple or C.card
end
auto.MouseButton1Click:Connect(function()
    if not viewerSession then
        status.Text="Primero entra con tu token"
        return
    end
    autoJoin=not autoJoin
    if autoJoin then
        armedAt=os.time()
        known={}
        for _,x in ipairs(eggs) do known[reportKey(x)]=true end
        status.Text="Auto join: esperando nuevo huevo"
    else
        status.Text="Auto join desactivado"
    end
    refreshToggle()
end)
-- Inicializa resultados (evita una pantalla vacía incluso sin conexión).
display()

local function api(path,method,payload,auth)
    if type(requestFn)~="function" then return nil,"Delta sin peticiones HTTP",0 end
    local args={
        Url=API..path, Method=method or "GET",
        Headers={["Content-Type"]="application/json"}
    }
    args.Headers["X-Roblox-UserId"]=tostring(player.UserId)
    if auth then args.Headers.Authorization="Bearer "..auth end
    if payload then args.Body=HttpService:JSONEncode(payload) end
    local ok,res=pcall(requestFn,args)
    if not ok or type(res)~="table" then return nil,"Error de red",0 end
    local httpCode=tonumber(res.StatusCode or res.Status or 0) or 0
    local parsed,content=pcall(HttpService.JSONDecode,HttpService,res.Body or "{}")
    if not parsed or type(content)~="table" then return nil,"Respuesta inválida",httpCode end
    if httpCode<200 or httpCode>=300 then
        return nil,tostring(content.error or ("HTTP "..httpCode)),httpCode
    end
    return content,nil,httpCode
end
enter.MouseButton1Click:Connect(function()
    if loginBusy then return end
    local raw=entry.Text:match("^%s*(.-)%s*$")
    local token=raw:match("#/acceso/([%w_%-]+)") or raw
    if #token<32 or not token:match("^[%w_%-]+$") then
        accessInfo.Text="Enlace o token inválido."
        return
    end
    loginBusy=true
    accessInfo.Text="Verificando token..."
    task.spawn(function()
        local result,err=api("/api/delta/redeem","POST",{token=token,user_id=player.UserId})
        loginBusy=false
        if not screen.Parent then return end
        if not result or result.role~="viewer" or type(result.session_token)~="string" then
            accessInfo.Text="Error: "..tostring(err or "sin acceso")
            status.Text="Revisa tu token de jugador"
            return
        end
        viewerSession=result.session_token
        entry.Text=""
        access.Visible=false
        list.Visible=true
        status.Text="Conectado a PVFinder Live Feed"
        display()
    end)
end)

-- Visor siempre abierto; peticiones HTTP en hilo aparte.
task.spawn(function()
    while screen.Parent do
        if viewerSession then
            local result,err,code=api("/api/feed","GET",nil,viewerSession)
            if result and type(result.items)=="table" then
                eggs=result.items
                local chosen=nil
                for _,x in ipairs(eggs) do
                    local k=reportKey(x)
                    local fresh=not known[k]
                    known[k]=true
                    local earning=tonumber(x.income_per_second)
                    local when=tonumber(x.updated_at) or 0
                    local job=tostring(x.server_id or "")
                    if autoJoin and fresh and earning and earning>=minIncome
                        and when>=armedAt-10 and when<=os.time()+120
                        and tonumber(x.place_id) and #job==36 then
                        if not chosen or earning>tonumber(chosen.income_per_second) then
                            chosen=x
                        end
                    end
                end
                display()
                if chosen then
                    autoJoin=false
                    refreshToggle()
                    if not join(chosen) then status.Text="JOIN no permitido por Roblox" end
                end
            elseif code==401 then
                viewerSession=nil
                eggs={}
                autoJoin=false
                refreshToggle()
                access.Visible=true
                list.Visible=false
                accessInfo.Text="Sesión vencida. Ingresa nuevo token."
                status.Text="Sesión vencida"
                display()
            else
                status.Text="Error Live Feed: "..tostring(err or code)
            end
        end
        task.wait(5)
    end
end)
