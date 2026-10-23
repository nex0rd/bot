--[[
    EntezHub | Murder Mystery 2 | Delta / mobile
    Иконки рисуются из Frame-ов (не грузятся из сети -> не могут не прогрузиться).
    // VERIFY: remotes MM2 (GetPlayerData / AH2 / Stab / HandleTouched / KnifeThrown) меняются патчами.
]]

local env = (getgenv and getgenv()) or _G
if env.EntezHubUnload then pcall(env.EntezHubUnload) end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local SoundService = game:GetService("SoundService")
local LP = Players.LocalPlayer

------------------------------------------------------------------ state
local Cfg = {
    ESP = false, ESPChams = true, ESPNames = true, ESPRole = true, ESPDist = true, ESPWall = true, ESPGun = true,
    Aim = false, AimMode = "Button", AimTarget = "Nearest", AimPart = "Head",
    AimFOV = 160, AimSmooth = 0.35, AimPredict = 0.08, AimWall = true, AimShowFOV = true,
    AutoShoot = false, AutoGrab = false, KillLoop = false,
    FlingTime = 3, Bypass = true, AntiFling = false,
    AutoFarm = false, FarmSpeed = 30, BagMax = 40, FarmReset = true,
    Speed = false, SpeedVal = 40, Jump = false, JumpVal = 70, InfJump = false,
    Fly = false, FlySpeed = 60, Noclip = false, Headless = false, Korblox = false,
    BoomVol = 1,
    Notify = true, AntiAFK = true, UIScale = 1,
    ToggleKey = Enum.KeyCode.RightShift,
}

local Hub = {
    Conns = {}, Alive = true, Selected = nil, Pickers = {},
    Flinging = false, FlingBusy = false, StopFling = false,
    Killing = false, ForceNoclip = false, FlyV = 0,
}
local function track(c) Hub.Conns[#Hub.Conns + 1] = c return c end

local RoleColor = {
    Murderer = Color3.fromRGB(255, 64, 64),
    Sheriff = Color3.fromRGB(64, 150, 255),
    Innocent = Color3.fromRGB(90, 235, 140),
}

------------------------------------------------------------------ helpers
local function hrp(p) local c = p and p.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function hum(p) local c = p and p.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function alive(p) local h = hum(p) return h ~= nil and h.Health > 0 and hrp(p) ~= nil end

local function safeParent(inst)
    pcall(function()
        if gethui then inst.Parent = gethui() else inst.Parent = CoreGui end
    end)
    if not inst.Parent then pcall(function() inst.Parent = CoreGui end) end
    if not inst.Parent then inst.Parent = LP:WaitForChild("PlayerGui") end
end

local function new(class, props, parent)
    local o = Instance.new(class)
    props = props or {}
    if o:IsA("GuiObject") and props.BorderSizePixel == nil then o.BorderSizePixel = 0 end
    if o:IsA("GuiButton") and props.AutoButtonColor == nil then o.AutoButtonColor = false end
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function tween(o, t, props, style, dir)
    local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

-- roles ----------------------------------------------------------
local RoleCache = {}
task.spawn(function()
    while Hub.Alive do
        pcall(function()
            local rf = game:GetService("ReplicatedStorage"):FindFirstChild("GetPlayerData", true) -- VERIFY
            if rf and rf:IsA("RemoteFunction") then
                local data = rf:InvokeServer()
                if type(data) == "table" then
                    local nc = {}
                    for name, info in pairs(data) do
                        if type(info) == "table" and info.Role then
                            local r = info.Role
                            if r == "Hero" then r = "Sheriff" end
                            nc[tostring(name)] = r
                        end
                    end
                    RoleCache = nc
                end
            end
        end)
        task.wait(2)
    end
end)

local function toolRole(p)
    local c = p.Character
    if c then
        if c:FindFirstChild("Knife") then return "Murderer" end
        if c:FindFirstChild("Gun") then return "Sheriff" end
    end
    local bp = p:FindFirstChildOfClass("Backpack")
    if bp then
        if bp:FindFirstChild("Knife") then return "Murderer" end
        if bp:FindFirstChild("Gun") then return "Sheriff" end
    end
end

local function getRole(p)
    local r = toolRole(p)
    if r then return r end
    local cached = RoleCache[p.Name]
    if cached == "Murderer" or cached == "Sheriff" then return cached end
    return "Innocent"
end

local function playerByRole(role)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and alive(p) and getRole(p) == role then return p end
    end
end

-- visibility ray -------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local ignoreT = 0
local function refreshIgnore()
    if tick() - ignoreT < 0.25 then return end
    ignoreT = tick()
    local list = {}
    if Workspace.CurrentCamera then list[1] = Workspace.CurrentCamera end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then list[#list + 1] = p.Character end
    end
    rayParams.FilterDescendantsInstances = list
end
local function visible(part)
    local cam = Workspace.CurrentCamera
    if not cam or not part then return false end
    refreshIgnore()
    local o = cam.CFrame.Position
    return Workspace:Raycast(o, part.Position - o, rayParams) == nil
end

------------------------------------------------------------------ theme / ui utils
local T = {
    bg0 = Color3.fromRGB(10, 10, 12), bg1 = Color3.fromRGB(16, 16, 19),
    bg2 = Color3.fromRGB(24, 24, 28), bg3 = Color3.fromRGB(36, 36, 42),
    line = Color3.fromRGB(48, 48, 56), text = Color3.fromRGB(240, 240, 244),
    sub = Color3.fromRGB(140, 140, 152), accent = Color3.fromRGB(235, 235, 240),
}
local accentSubs = {}
local function onAccent(fn) accentSubs[#accentSubs + 1] = fn fn(T.accent) end
local function setAccent(c) T.accent = c for _, f in ipairs(accentSubs) do pcall(f, c) end end

local function corner(o, r) return new("UICorner", {CornerRadius = r or UDim.new(1, 0)}, o) end
local function stroke(o, c, th, tr)
    return new("UIStroke", {Color = c or T.line, Thickness = th or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o)
end

local function pressFx(trigger, target)
    local sc = new("UIScale", {Scale = 1}, target)
    trigger.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            tween(sc, 0.1, {Scale = 0.96})
        end
    end)
    trigger.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            tween(sc, 0.18, {Scale = 1}, Enum.EasingStyle.Back)
        end
    end)
end

-- icons: все белые, собраны из фигур ----------------------------------
local Icons = {
    Combat = function(sh)
        sh(.5, .5, .64, .64, {r = true, ring = true}); sh(.5, .5, .12, .12, {r = true})
        sh(.5, .1, .09, .22, {r = true}); sh(.5, .9, .09, .22, {r = true})
        sh(.1, .5, .22, .09, {r = true}); sh(.9, .5, .22, .09, {r = true})
    end,
    Fling = function(sh)
        sh(.46, .28, .62, .1, {r = true}); sh(.56, .5, .74, .1, {r = true}); sh(.42, .72, .52, .1, {r = true})
        sh(.84, .28, .16, .16, {r = true, ring = true})
    end,
    Teleports = function(sh)
        sh(.5, .38, .52, .52, {r = true, ring = true}); sh(.5, .38, .16, .16, {r = true})
        sh(.5, .74, .2, .2, {rot = 45}); sh(.5, .93, .46, .07, {r = true})
    end,
    AutoFarm = function(sh)
        sh(.5, .5, .8, .8, {r = true, ring = true}); sh(.5, .5, .09, .46, {r = true})
        sh(.5, .38, .3, .08, {r = true}); sh(.5, .62, .3, .08, {r = true})
    end,
    Player = function(sh)
        sh(.5, .3, .36, .36, {r = true}); sh(.5, .98, .78, .66, {r = true})
    end,
    Settings = function(sh, size)
        sh(.5, .5, .58, .58, {r = true, ring = true, th = math.max(2, size * 0.12)})
        for i = 0, 7 do
            local a = math.rad(i * 45)
            sh(.5 + math.cos(a) * .38, .5 + math.sin(a) * .38, .16, .16, {rot = i * 45})
        end
    end,
    ["UI Custom"] = function(sh)
        sh(.5, .5, .84, .84, {r = true, ring = true})
        sh(.36, .4, .13, .13, {r = true}); sh(.56, .32, .13, .13, {r = true})
        sh(.67, .54, .13, .13, {r = true}); sh(.46, .66, .13, .13, {r = true})
    end,
    Minimize = function(sh) sh(.5, .5, .6, .1, {r = true}) end,
    Close = function(sh) sh(.5, .5, .74, .1, {r = true, rot = 45}); sh(.5, .5, .74, .1, {r = true, rot = -45}) end,
    Up = function(sh) sh(.35, .5, .46, .1, {r = true, rot = -45}); sh(.65, .5, .46, .1, {r = true, rot = 45}) end,
    Down = function(sh) sh(.35, .5, .46, .1, {r = true, rot = 45}); sh(.65, .5, .46, .1, {r = true, rot = -45}) end,
}

local function icon(name, size)
    local f = new("Frame", {Name = "Icon_" .. name, Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, ClipsDescendants = true})
    local th = math.max(1.5, size * 0.085)
    local white = Color3.new(1, 1, 1)
    local function sh(cx, cy, w, h, o)
        o = o or {}
        local s = new("Frame", {
            AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(cx, cy), Size = UDim2.fromScale(w, h),
            BackgroundColor3 = white, BackgroundTransparency = o.ring and 1 or 0, Rotation = o.rot or 0,
        }, f)
        if o.r then corner(s) end
        if o.ring then new("UIStroke", {Color = white, Thickness = o.th or th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, s) end
        return s
    end
    if Icons[name] then Icons[name](sh, size) end
    return f
end

------------------------------------------------------------------ gui root
local Gui = new("ScreenGui", {Name = "EntezHub", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1000})
safeParent(Gui)

local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "EntezESP"
safeParent(ESPFolder)

local NotifyHolder = new("Frame", {AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -18),
    Size = UDim2.fromOffset(320, 200), BackgroundTransparency = 1}, Gui)
new("UIListLayout", {Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom,
    HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder}, NotifyHolder)

local function notify(text)
    if not Cfg.Notify then return end
    local l = new("TextLabel", {Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = T.bg1, BackgroundTransparency = 1, Text = text, TextColor3 = T.text, TextTransparency = 1,
        Font = Enum.Font.GothamMedium, TextSize = 12}, NotifyHolder)
    corner(l)
    new("UIPadding", {PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16)}, l)
    local st = stroke(l, T.line, 1, 1)
    tween(l, .25, {BackgroundTransparency = 0, TextTransparency = 0})
    tween(st, .25, {Transparency = 0})
    task.delay(2.4, function()
        if l.Parent then
            tween(l, .3, {BackgroundTransparency = 1, TextTransparency = 1})
            tween(st, .3, {Transparency = 1})
            task.delay(.35, function() l:Destroy() end)
        end
    end)
end

-- единая система драга (окно, слайдеры, mini-кнопка) ----------------------
local drag = {fn = nil, input = nil, mouse = false, onEnd = nil}
track(UIS.InputChanged:Connect(function(i)
    if drag.fn and (i.UserInputType == Enum.UserInputType.MouseMovement or i == drag.input) then drag.fn(i.Position) end
end))
track(UIS.InputEnded:Connect(function(i)
    if drag.fn and (i == drag.input or (drag.mouse and i.UserInputType == Enum.UserInputType.MouseButton1)) then
        local e = drag.onEnd
        drag.fn, drag.input, drag.onEnd = nil, nil, nil
        if e then e() end
    end
end))
local function beginDrag(input, fn, onEnd)
    drag.fn, drag.input, drag.onEnd = fn, input, onEnd
    drag.mouse = input.UserInputType == Enum.UserInputType.MouseButton1
    fn(input.Position)
end

------------------------------------------------------------------ ESP
local ESPObjs = {}
local function makeESP(p)
    if p == LP or ESPObjs[p] then return end
    local hl = new("Highlight", {FillTransparency = 0.55, OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false}, ESPFolder)
    local bb = new("BillboardGui", {Size = UDim2.fromOffset(180, 38), StudsOffset = Vector3.new(0, 3.1, 0),
        AlwaysOnTop = true, LightInfluence = 0, ResetOnSpawn = false, Enabled = false}, ESPFolder)
    local nl = new("TextLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.GothamBold,
        TextSize = 14, TextStrokeTransparency = 0.35, TextColor3 = Color3.new(1, 1, 1), Text = ""}, bb)
    local il = new("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 16),
        Font = Enum.Font.GothamMedium, TextSize = 11, TextStrokeTransparency = 0.35, TextColor3 = Color3.new(1, 1, 1), Text = ""}, bb)
    ESPObjs[p] = {hl = hl, bb = bb, nl = nl, il = il}
end
local function dropESP(p)
    local o = ESPObjs[p]
    if o then o.hl:Destroy() o.bb:Destroy() ESPObjs[p] = nil end
end

local gunHL = new("Highlight", {FillColor = Color3.fromRGB(255, 215, 90), OutlineColor = Color3.fromRGB(255, 215, 90),
    FillTransparency = 0.4, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false}, ESPFolder)
local gunBB = new("BillboardGui", {Size = UDim2.fromOffset(120, 20), StudsOffset = Vector3.new(0, 2, 0), AlwaysOnTop = true,
    LightInfluence = 0, Enabled = false}, ESPFolder)
local gunLbl = new("TextLabel", {BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 13,
    TextColor3 = Color3.fromRGB(255, 215, 90), TextStrokeTransparency = 0.35, Text = "GUN"}, gunBB)

local function updateESP()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local camPos = cam.CFrame.Position
    for p, o in pairs(ESPObjs) do
        local c, h = p.Character, hum(p)
        local r = c and c:FindFirstChild("HumanoidRootPart")
        if Cfg.ESP and c and r and h and h.Health > 0 then
            local role = getRole(p)
            local col = RoleColor[role]
            local head = c:FindFirstChild("Head") or r
            local meters = (camPos - r.Position).Magnitude * 0.28 -- 1 stud ~ 0.28 m
            local vis = true
            if Cfg.ESPWall then vis = visible(head) end
            o.hl.Adornee = c
            o.hl.Enabled = Cfg.ESPChams
            o.hl.FillColor, o.hl.OutlineColor = col, col
            o.hl.FillTransparency = vis and 0.45 or 0.78
            o.bb.Adornee = head
            o.bb.Enabled = true
            o.nl.Visible = Cfg.ESPNames
            o.nl.Text = p.DisplayName
            o.nl.TextColor3 = col
            local parts = {}
            if Cfg.ESPRole then parts[#parts + 1] = role end
            if Cfg.ESPDist then parts[#parts + 1] = string.format("%.0fm", meters) end
            if Cfg.ESPWall then parts[#parts + 1] = vis and "VISIBLE" or "BEHIND WALL" end
            o.il.Text = table.concat(parts, "  •  ")
            if Cfg.ESPWall then
                o.il.TextColor3 = vis and Color3.fromRGB(150, 255, 170) or Color3.fromRGB(190, 190, 200)
            else
                o.il.TextColor3 = Color3.new(1, 1, 1)
            end
        else
            o.hl.Enabled = false
            o.bb.Enabled = false
        end
    end
    local gd = Workspace:FindFirstChild("GunDrop")
    if Cfg.ESP and Cfg.ESPGun and gd then
        gunHL.Adornee = gd; gunHL.Enabled = true
        gunBB.Adornee = gd; gunBB.Enabled = true
        local pos = gd:IsA("BasePart") and gd.Position or gd:GetPivot().Position
        gunLbl.Text = string.format("GUN  •  %.0fm", (camPos - pos).Magnitude * 0.28)
    else
        gunHL.Enabled = false; gunBB.Enabled = false
    end
end

for _, p in ipairs(Players:GetPlayers()) do makeESP(p) end
track(Players.PlayerAdded:Connect(makeESP))
track(Players.PlayerRemoving:Connect(dropESP))
track(RunService.RenderStepped:Connect(function() pcall(updateESP) end))

------------------------------------------------------------------ AIMBOT
local AimHeld = false
local function aimPartOf(p)
    local c = p.Character
    if not c then return nil end
    if Cfg.AimPart == "Head" then return c:FindFirstChild("Head") or hrp(p) end
    return hrp(p)
end
local function pickTarget()
    local cam = Workspace.CurrentCamera
    local center = cam.ViewportSize / 2
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and alive(p) then
            local want = Cfg.AimTarget
            if want == "Nearest" or want == getRole(p) then
                local part = aimPartOf(p)
                if part then
                    local v, on = cam:WorldToViewportPoint(part.Position)
                    if on then
                        local d = (Vector2.new(v.X, v.Y) - center).Magnitude
                        if d <= Cfg.AimFOV and (not bestD or d < bestD) and (not Cfg.AimWall or visible(part)) then
                            best, bestD = part, d
                        end
                    end
                end
            end
        end
    end
    return best
end
RunService:BindToRenderStep("EntezAim", Enum.RenderPriority.Camera.Value + 1, function()
    if not Cfg.Aim then return end
    if Cfg.AimMode == "Button" and not AimHeld then return end
    local part = pickTarget()
    if not part then return end
    local cam = Workspace.CurrentCamera
    local pos = part.Position + part.AssemblyLinearVelocity * Cfg.AimPredict
    cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, pos), Cfg.AimSmooth)
end)
track(UIS.InputBegan:Connect(function(i, gp)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then AimHeld = true end
end))
track(UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then AimHeld = false end
end))

------------------------------------------------------------------ tools / combat
local function findTool(name)
    local c = LP.Character
    local t = c and c:FindFirstChild(name)
    if t then return t end
    local bp = LP:FindFirstChildOfClass("Backpack")
    return bp and bp:FindFirstChild(name)
end
local function equip(name)
    local t, h = findTool(name), hum(LP)
    if t and h and t.Parent ~= LP.Character then h:EquipTool(t) task.wait(0.12) end
    local c = LP.Character
    return c and c:FindFirstChild(name)
end

local function shootAt(pos)
    local gun = equip("Gun")
    if not gun then return false end
    local cb = gun:FindFirstChild("CreateBeam", true) -- VERIFY
    local rf = cb and (cb:IsA("RemoteFunction") and cb or cb:FindFirstChildOfClass("RemoteFunction"))
    if rf then
        pcall(function() rf:InvokeServer(1, pos, "AH2") end) -- VERIFY: сигнатура/ключ
    else
        pcall(function() gun:Activate() end)
    end
    return true
end
local function throwAt(pos)
    local knife = equip("Knife")
    local r = hrp(LP)
    if not (knife and r) then return false end
    local ev = knife:FindFirstChild("KnifeThrown", true) or knife:FindFirstChild("Throw", true) -- VERIFY
    if ev and ev:IsA("RemoteEvent") then
        pcall(function() ev:FireServer(CFrame.new(r.Position, pos), CFrame.new(pos)) end)
        return true
    end
    return false
end

local lastShot = 0
track(RunService.Heartbeat:Connect(function()
    if not Cfg.AutoShoot or Hub.Flinging or Hub.Killing then return end
    if tick() - lastShot < 1.1 or not alive(LP) then return end
    local role = getRole(LP)
    local myr = hrp(LP)
    if role == "Sheriff" then
        local m = playerByRole("Murderer")
        local mr = m and hrp(m)
        if mr then
            local head = m.Character:FindFirstChild("Head") or mr
            if (mr.Position - myr.Position).Magnitude < 160 and visible(head) then
                lastShot = tick()
                task.spawn(shootAt, mr.Position + mr.AssemblyLinearVelocity * 0.12)
            end
        end
    elseif role == "Murderer" then
        local s = playerByRole("Sheriff")
        local sr = s and hrp(s)
        if sr then
            local head = s.Character:FindFirstChild("Head") or sr
            if (sr.Position - myr.Position).Magnitude < 90 and visible(head) then
                lastShot = tick()
                task.spawn(throwAt, sr.Position + sr.AssemblyLinearVelocity * 0.15)
            end
        end
    end
end))

local function grabGun()
    local gd, r = Workspace:FindFirstChild("GunDrop"), hrp(LP)
    if not (gd and r) then notify("GunDrop нет") return end
    local old = r.CFrame
    local cf = gd:IsA("BasePart") and gd.CFrame or gd:GetPivot()
    if firetouchinterest and gd:IsA("BasePart") then
        pcall(function() firetouchinterest(r, gd, 0) firetouchinterest(r, gd, 1) end)
        task.wait(0.15)
    end
    if not findTool("Gun") then
        r.CFrame = cf + Vector3.new(0, 2, 0)
        task.wait(0.35)
        if r.Parent then r.CFrame = old end
    end
end
task.spawn(function()
    while Hub.Alive do
        task.wait(0.5)
        if Cfg.AutoGrab and alive(LP) and not Hub.Flinging and not Hub.Killing
            and Workspace:FindFirstChild("GunDrop") and getRole(LP) ~= "Murderer" and not findTool("Gun") then
            pcall(grabGun)
            task.wait(1)
        end
    end
end)

local function stab(knife, tr)
    pcall(function() knife:Activate() end)
    pcall(function()
        local h = knife:FindFirstChild("Handle")
        if h and firetouchinterest then firetouchinterest(h, tr, 0) firetouchinterest(h, tr, 1) end
    end)
    pcall(function()
        local ev = knife:FindFirstChild("Stab", true) -- VERIFY
        if ev and ev:IsA("RemoteEvent") then ev:FireServer("Slash") end
        local ht = knife:FindFirstChild("HandleTouched", true) -- VERIFY
        if ht and ht:IsA("RemoteEvent") then ht:FireServer(tr) end
    end)
end
local function killAllOnce()
    if getRole(LP) ~= "Murderer" then notify("ты не murderer") return end
    local knife = equip("Knife")
    if not knife then notify("нет ножа") return end
    local mr0 = hrp(LP)
    local old = mr0 and mr0.CFrame
    Hub.Killing = true
    for _, p in ipairs(Players:GetPlayers()) do
        if not (Hub.Alive and Hub.Killing) then break end
        if p ~= LP and alive(p) then
            local t0 = tick()
            while Hub.Alive and Hub.Killing and alive(p) and alive(LP) and tick() - t0 < 1.5 do
                local tr, mr = hrp(p), hrp(LP)
                if not (tr and mr) then break end
                mr.CFrame = CFrame.lookAt((tr.CFrame * CFrame.new(0, 0, 2.4)).Position, tr.Position)
                knife = equip("Knife") or knife
                stab(knife, tr)
                task.wait(0.07)
            end
        end
    end
    Hub.Killing = false
    local mr = hrp(LP)
    if mr and old then mr.CFrame = old end
end
task.spawn(function()
    while Hub.Alive do
        task.wait(0.5)
        if Cfg.KillLoop and not Hub.Killing and alive(LP) and getRole(LP) == "Murderer" then
            pcall(killAllOnce)
        end
    end
end)

------------------------------------------------------------------ FLING
local FlingParts = {"HumanoidRootPart", "Head", "UpperTorso", "Torso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftUpperArm", "RightUpperArm"}
local FlingOffs = {Vector3.new(0, 1.5, 0), Vector3.new(0, -1.5, 0), Vector3.new(2.2, 1.5, -2.2), Vector3.new(-2.2, -1.5, 2.2), Vector3.new(0, 0, 0)}

local function flingPlayer(tp, maxTime)
    local myr, myh = hrp(LP), hum(LP)
    if not (myr and myh and tp and tp ~= LP and alive(tp)) then return false end
    if Hub.Flinging then return false end
    Hub.Flinging = true
    local cam = Workspace.CurrentCamera
    local oldCF = myr.CFrame
    local oldH = Workspace.FallenPartsDestroyHeight
    pcall(function() Workspace.FallenPartsDestroyHeight = 0 / 0 end)
    local names = Cfg.Bypass and FlingParts or {"HumanoidRootPart"}
    local startRoot = hrp(tp)
    local startPos = startRoot.Position
    local t0, lastSwitch = tick(), tick()
    local ang, idx, partIdx, flung = 0, 0, 1, false
    while Hub.Alive and not Hub.StopFling and tick() - t0 < maxTime do
        local tc, th = tp.Character, hum(tp)
        if not (tc and th and th.Health > 0 and myr.Parent) then break end
        local part
        for i = 0, #names - 1 do
            part = tc:FindFirstChild(names[((partIdx - 1 + i) % #names) + 1])
            if part then break end
        end
        if not part then break end
        pcall(function() cam.CameraSubject = th end)
        ang = ang + 120
        idx = (idx % #FlingOffs) + 1
        local pos = part.Position + part.AssemblyLinearVelocity * 0.07 + FlingOffs[idx]
        myr.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(ang), 0, math.rad(ang * 0.5))
        myr.AssemblyLinearVelocity = Vector3.new(1e6, 1e6, 1e6)
        myr.AssemblyAngularVelocity = Vector3.new(1e6, 1e6, 1e6)
        RunService.Heartbeat:Wait()
        local tr = tc:FindFirstChild("HumanoidRootPart")
        if tr and ((tr.Position - startPos).Magnitude > 140 or tr.AssemblyLinearVelocity.Magnitude > 350) then
            flung = true
            break
        end
        -- обход античитерских анти-флингов: ротация по частям тела / оффсетам
        if Cfg.Bypass and tick() - lastSwitch > 0.9 then
            partIdx = (partIdx % #names) + 1
            lastSwitch = tick()
        end
    end
    for _ = 1, 10 do
        if myr.Parent then
            myr.AssemblyLinearVelocity = Vector3.zero
            myr.AssemblyAngularVelocity = Vector3.zero
            myr.CFrame = oldCF
        end
        RunService.Heartbeat:Wait()
    end
    pcall(function() cam.CameraSubject = myh end)
    pcall(function() Workspace.FallenPartsDestroyHeight = oldH end)
    Hub.Flinging = false
    return flung
end

local function runFling(list)
    if Hub.FlingBusy then notify("fling уже идёт") return end
    Hub.FlingBusy, Hub.StopFling = true, false
    task.spawn(function()
        for _, p in ipairs(list) do
            if Hub.StopFling or not Hub.Alive then break end
            if p and p.Parent and alive(p) then
                local ok = flingPlayer(p, Cfg.FlingTime)
                notify((ok and "flung: " or "не вышло: ") .. p.DisplayName)
                task.wait(0.15)
            end
        end
        Hub.FlingBusy = false
    end)
end
local function allOthers()
    local l = {}
    for _, p in ipairs(Players:GetPlayers()) do if p ~= LP then l[#l + 1] = p end end
    return l
end

-- anti fling + noclip + velocity clamp
track(RunService.Stepped:Connect(function()
    local c = LP.Character
    if (Cfg.Noclip or Hub.ForceNoclip) and c then
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") then d.CanCollide = false end
        end
    end
    if Cfg.AntiFling and not Hub.Flinging then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                for _, d in ipairs(p.Character:GetChildren()) do
                    if d:IsA("BasePart") then d.CanCollide = false end
                end
            end
        end
    end
end))
track(RunService.Heartbeat:Connect(function()
    if Cfg.AntiFling and not Hub.Flinging and not Cfg.Fly and not Hub.ForceNoclip then
        local r = hrp(LP)
        if r and (r.AssemblyLinearVelocity.Magnitude > 160 or r.AssemblyAngularVelocity.Magnitude > 60) then
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end
    end
end))

------------------------------------------------------------------ TELEPORTS
local function tpTo(cf)
    local r = hrp(LP)
    if r then r.CFrame = cf r.AssemblyLinearVelocity = Vector3.zero end
end
local function lobbyCF()
    local lobby = Workspace:FindFirstChild("Lobby")
    if lobby then
        local sp = lobby:FindFirstChild("Spawns")
        if sp then
            local c = sp:GetChildren()
            if #c > 0 then
                local s = c[math.random(#c)]
                if s:IsA("BasePart") then return s.CFrame + Vector3.new(0, 4, 0) end
            end
        end
        for _, d in ipairs(lobby:GetDescendants()) do
            if d:IsA("SpawnLocation") then return d.CFrame + Vector3.new(0, 4, 0) end
        end
        return lobby:GetPivot() + Vector3.new(0, 6, 0)
    end
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("SpawnLocation") then return d.CFrame + Vector3.new(0, 4, 0) end
    end
end
local function getCoinContainer()
    for _, m in ipairs(Workspace:GetChildren()) do
        if m:IsA("Model") then
            local cc = m:FindFirstChild("CoinContainer")
            if cc then return cc, m end
        end
    end
end
local function mapCF()
    local cc, m = getCoinContainer()
    if not m then return nil end
    local sp = m:FindFirstChild("Spawns")
    if sp then
        local c = sp:GetChildren()
        if #c > 0 and c[1]:IsA("BasePart") then return c[math.random(#c)].CFrame + Vector3.new(0, 4, 0) end
    end
    return m:GetPivot() + Vector3.new(0, 8, 0)
end
local function tpToPlayer(p)
    local r = p and hrp(p)
    if not r then notify("игрок недоступен") return end
    tpTo(r.CFrame * CFrame.new(0, 0, 3))
end
local SavedPos

------------------------------------------------------------------ AUTOFARM
local FarmLabel
local function farmStatus(t) if FarmLabel then FarmLabel.Text = t end end

local function tweenTo(cf, speed)
    local r = hrp(LP)
    if not r then return end
    local dist = (cf.Position - r.Position).Magnitude
    local dur = math.max(dist / speed, 0.05)
    local tw = TweenService:Create(r, TweenInfo.new(dur, Enum.EasingStyle.Linear), {CFrame = cf})
    tw:Play()
    local t0 = tick()
    while tick() - t0 < dur + 0.03 do
        if not (Cfg.AutoFarm and Hub.Alive and alive(LP)) then tw:Cancel() break end
        r.AssemblyLinearVelocity = Vector3.zero
        task.wait()
    end
    tw:Cancel()
end

task.spawn(function()
    local visited, collected, lastCC, done = {}, 0, nil, false
    while Hub.Alive do
        task.wait(0.1)
        if Cfg.AutoFarm and alive(LP) and not Hub.Flinging then
            local cc = getCoinContainer()
            if cc ~= lastCC then visited, collected, lastCC, done = {}, 0, cc, false end
            if not cc then
                Hub.ForceNoclip = false
                farmStatus("Ждём раунд…")
            elseif done then
                Hub.ForceNoclip = false
                farmStatus("Сумка полна — ждём новый раунд")
            elseif collected >= Cfg.BagMax then
                done = true
                if Cfg.FarmReset then
                    local h = hum(LP)
                    if h then h.Health = 0 end
                end
            else
                local r = hrp(LP)
                local best, bd
                for _, c in ipairs(cc:GetChildren()) do
                    if c:IsA("BasePart") and not visited[c] and c.Parent then
                        local d = (c.Position - r.Position).Magnitude
                        if not bd or d < bd then best, bd = c, d end
                    end
                end
                if best then
                    Hub.ForceNoclip = true
                    farmStatus(string.format("Монет: %d / %d", collected, Cfg.BagMax))
                    tweenTo(best.CFrame + Vector3.new(0, 2, 0), Cfg.FarmSpeed)
                    visited[best] = true
                    collected = collected + 1
                else
                    Hub.ForceNoclip = false
                    farmStatus("Монеты кончились")
                end
            end
        else
            Hub.ForceNoclip = false
        end
    end
end)

------------------------------------------------------------------ PLAYER
local speedWas, jumpWas = false, false
track(RunService.Heartbeat:Connect(function()
    local h = hum(LP)
    if not h then return end
    if Cfg.Speed then h.WalkSpeed = Cfg.SpeedVal speedWas = true
    elseif speedWas then h.WalkSpeed = 16 speedWas = false end
    if Cfg.Jump then h.UseJumpPower = true h.JumpPower = Cfg.JumpVal jumpWas = true
    elseif jumpWas then h.UseJumpPower = true h.JumpPower = 50 jumpWas = false end
end))
track(UIS.JumpRequest:Connect(function()
    if Cfg.InfJump then
        local h = hum(LP)
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

local flyBV, flyBG
local function stopFly()
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local h = hum(LP)
    if h then h.PlatformStand = false end
end
local function startFly()
    local r, h = hrp(LP), hum(LP)
    if not (r and h) then return end
    stopFly()
    flyBV = new("BodyVelocity", {MaxForce = Vector3.new(9e9, 9e9, 9e9), Velocity = Vector3.zero}, r)
    flyBG = new("BodyGyro", {MaxTorque = Vector3.new(9e9, 9e9, 9e9), P = 9e4, CFrame = r.CFrame}, r)
    h.PlatformStand = true
end
track(RunService.RenderStepped:Connect(function()
    if not Cfg.Fly then return end
    local r, h = hrp(LP), hum(LP)
    if not (r and h) then return end
    if not flyBV or flyBV.Parent ~= r then startFly() end
    local cam = Workspace.CurrentCamera
    local md = h.MoveDirection
    local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
    local flat = Vector3.new(look.X, 0, look.Z)
    flat = flat.Magnitude < 0.01 and Vector3.new(0, 0, -1) or flat.Unit
    local fr = Vector3.new(right.X, 0, right.Z)
    fr = fr.Magnitude < 0.01 and Vector3.new(1, 0, 0) or fr.Unit
    local v = Hub.FlyV
    if UIS:IsKeyDown(Enum.KeyCode.Space) then v = v + 1 end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then v = v - 1 end
    flyBV.Velocity = (look * md:Dot(flat) + right * md:Dot(fr)) * Cfg.FlySpeed + Vector3.new(0, v * Cfg.FlySpeed, 0)
    flyBG.CFrame = CFrame.lookAt(r.Position, r.Position + flat)
end))

-- fake headless / korblox (клиентские, видишь только ты) ---------------------
local Saved = {}
local function applyHeadless(on)
    local c = LP.Character
    local head = c and c:FindFirstChild("Head")
    if not head then return end
    local f = head:FindFirstChildOfClass("Decal")
    if on then
        if Saved.headT == nil then Saved.headT = head.Transparency end
        head.Transparency = 1
        if f then
            if Saved.faceT == nil then Saved.faceT = f.Transparency end
            f.Transparency = 1
        end
    else
        head.Transparency = Saved.headT or 0
        if f then f.Transparency = Saved.faceT or 0 end
        Saved.headT, Saved.faceT = nil, nil
    end
end
local KORB = { -- VERIFY: id-шники Korblox Deathspeaker
    RightUpperLeg = {902942096, 902843398},
    RightLowerLeg = {902942093, 902843398},
    RightFoot = {902942089, 902843398},
}
local function applyKorblox(on)
    local c = LP.Character
    if not c then return end
    local leg6 = c:FindFirstChild("Right Leg")
    if leg6 and leg6:IsA("BasePart") then leg6.Transparency = on and 1 or 0 end
    for name, ids in pairs(KORB) do
        local p = c:FindFirstChild(name)
        if p and p:IsA("MeshPart") then
            local key = "k" .. name
            if on then
                if not Saved[key] then Saved[key] = {p.MeshId, p.TextureID, p.Transparency} end
                local ok = pcall(function()
                    p.MeshId = "rbxassetid://" .. ids[1]
                    p.TextureID = "rbxassetid://" .. ids[2]
                end)
                if not ok then p.Transparency = 1 end
            elseif Saved[key] then
                local s = Saved[key]
                pcall(function() p.MeshId = s[1] p.TextureID = s[2] end)
                p.Transparency = s[3]
                Saved[key] = nil
            end
        end
    end
end
track(LP.CharacterAdded:Connect(function()
    Saved = {}
    task.wait(1)
    if Cfg.Fly then startFly() end
    if Cfg.Headless then applyHeadless(true) end
    if Cfg.Korblox then applyKorblox(true) end
end))
task.spawn(function()
    while Hub.Alive do
        task.wait(1)
        if Cfg.Headless then pcall(applyHeadless, true) end
        if Cfg.Korblox then pcall(applyKorblox, true) end
    end
end)

-- boombox (локально — слышишь только ты) -----------------------------------
local Boom = new("Sound", {Name = "EntezBoom", Volume = 1, Looped = true}, SoundService)
local function boomPlay(id)
    local n = (tostring(id):gsub("%D", ""))
    if n == "" then notify("введи ID аудио") return end
    Boom.SoundId = "rbxassetid://" .. n
    Boom.Volume = Cfg.BoomVol
    Boom:Play()
end

track(LP.Idled:Connect(function()
    if Cfg.AntiAFK then
        pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end)
    end
end))

------------------------------------------------------------------ UI build
local Page = {}
Page.__index = Page
local Pages, CurrentPage, TabBtns = {}, nil, {}
local PageHost, Main, WinScale, Mini, MiniScale
local Names = {"Combat", "Fling", "Teleports", "AutoFarm", "Player", "Settings", "UI Custom"}
local minimized = false

local function baseScale()
    local cam = Workspace.CurrentCamera
    local v = cam and cam.ViewportSize or Vector2.new(800, 400)
    return math.clamp(math.min((v.X - 24) / 540, (v.Y - 24) / 320), 0.5, 1.15)
end
local function targetScale() return baseScale() * Cfg.UIScale end

local function rowLabel(r, text, reserve)
    return new("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -(14 + (reserve or 60)), 1, 0), Text = text, TextColor3 = T.text,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd}, r)
end

function Page:Row(h)
    self.n = self.n + 1
    local r = new("Frame", {Size = UDim2.new(1, 0, 0, h or 34), BackgroundColor3 = T.bg2, LayoutOrder = self.n}, self.Scroll)
    corner(r)
    stroke(r, T.line, 1, 0.35)
    return r
end

function Page:Section(text)
    self.n = self.n + 1
    local l = new("TextLabel", {Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = string.upper(text),
        TextColor3 = T.sub, Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = self.n}, self.Scroll)
    new("UIPadding", {PaddingLeft = UDim.new(0, 8)}, l)
end

function Page:Toggle(text, key, cb)
    local r = self:Row(34)
    rowLabel(r, text, 64)
    local track_ = new("Frame", {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0),
        Size = UDim2.fromOffset(42, 22), BackgroundColor3 = T.bg3}, r)
    corner(track_)
    local knob = new("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 3, .5, 0),
        Size = UDim2.fromOffset(16, 16), BackgroundColor3 = T.sub}, track_)
    corner(knob)
    local btn = new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = ""}, r)
    local function paint(anim)
        local on = Cfg[key]
        local p1 = {BackgroundColor3 = on and T.accent or T.bg3}
        local p2 = {Position = on and UDim2.new(1, -19, .5, 0) or UDim2.new(0, 3, .5, 0),
            BackgroundColor3 = on and T.bg0 or T.sub}
        if anim then
            tween(track_, .22, p1) tween(knob, .22, p2)
        else
            for k, v in pairs(p1) do track_[k] = v end
            for k, v in pairs(p2) do knob[k] = v end
        end
    end
    onAccent(function() paint(false) end)
    btn.Activated:Connect(function()
        Cfg[key] = not Cfg[key]
        paint(true)
        if cb then task.spawn(cb, Cfg[key]) end
    end)
    pressFx(btn, r)
end

function Page:Slider(text, key, min, max, step, cb)
    local r = self:Row(48)
    new("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 5), Size = UDim2.new(.6, 0, 0, 18),
        Text = text, TextColor3 = T.text, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left}, r)
    local val = new("TextLabel", {BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 5),
        Size = UDim2.new(.4, 0, 0, 18), Text = "", TextColor3 = T.sub, Font = Enum.Font.GothamMedium, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right}, r)
    local bar = new("Frame", {Position = UDim2.new(0, 14, 1, -15), Size = UDim2.new(1, -28, 0, 6), BackgroundColor3 = T.bg3}, r)
    corner(bar)
    local fill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.accent}, bar)
    corner(fill)
    local knob = new("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(0, .5),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = T.accent}, bar)
    corner(knob)
    local hit = new("TextButton", {Position = UDim2.new(0, 6, 1, -28), Size = UDim2.new(1, -12, 0, 26),
        BackgroundTransparency = 1, Text = ""}, r)
    local fmt = (step < 1) and "%.2f" or "%d"
    local function visual(v, anim)
        local a = (v - min) / (max - min)
        val.Text = string.format(fmt, v)
        local sz, ps = UDim2.fromScale(a, 1), UDim2.fromScale(a, .5)
        if anim then tween(fill, .08, {Size = sz}) tween(knob, .08, {Position = ps})
        else fill.Size = sz knob.Position = ps end
    end
    onAccent(function(c) fill.BackgroundColor3 = c knob.BackgroundColor3 = c end)
    visual(Cfg[key], false)
    local scroll = self.Scroll
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            scroll.ScrollingEnabled = false
            beginDrag(i, function(pos)
                local a = math.clamp((pos.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
                local v = min + a * (max - min)
                v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
                Cfg[key] = v
                visual(v, true)
                if cb then cb(v) end
            end, function() scroll.ScrollingEnabled = true end)
        end
    end)
end

function Page:Choice(text, key, options, cb)
    local r = self:Row(34)
    rowLabel(r, text, 112)
    local pill = new("TextButton", {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0),
        Size = UDim2.fromOffset(96, 24), BackgroundColor3 = T.bg3, Text = tostring(Cfg[key]), TextColor3 = T.text,
        Font = Enum.Font.GothamMedium, TextSize = 11}, r)
    corner(pill)
    pill.Activated:Connect(function()
        local idx = 1
        for i, o in ipairs(options) do if o == Cfg[key] then idx = i end end
        Cfg[key] = options[(idx % #options) + 1]
        pill.Text = tostring(Cfg[key])
        if cb then cb(Cfg[key]) end
    end)
    pressFx(pill, pill)
end

function Page:Button(text, cb)
    local r = self:Row(34)
    r.BackgroundColor3 = T.bg3
    local b = new("TextButton", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text,
        TextColor3 = T.text, Font = Enum.Font.GothamMedium, TextSize = 12}, r)
    b.MouseEnter:Connect(function() tween(r, .15, {BackgroundColor3 = T.line}) end)
    b.MouseLeave:Connect(function() tween(r, .15, {BackgroundColor3 = T.bg3}) end)
    b.Activated:Connect(function()
        tween(r, .08, {BackgroundColor3 = T.line})
        task.delay(.12, function() tween(r, .2, {BackgroundColor3 = T.bg3}) end)
        task.spawn(function() local ok, e = pcall(cb) if not ok then warn("[EntezHub] " .. tostring(e)) end end)
    end)
    pressFx(b, r)
end

function Page:Input(text, placeholder, cb)
    local r = self:Row(34)
    rowLabel(r, text, 138)
    local tb = new("TextBox", {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -8, .5, 0), Size = UDim2.fromOffset(122, 24),
        BackgroundColor3 = T.bg3, Text = "", PlaceholderText = placeholder, PlaceholderColor3 = T.sub, TextColor3 = T.text,
        Font = Enum.Font.GothamMedium, TextSize = 11, ClearTextOnFocus = false}, r)
    corner(tb)
    tb.FocusLost:Connect(function() cb(tb.Text) end)
    return tb
end

function Page:Label(text)
    local r = self:Row(30)
    local l = rowLabel(r, text, 28)
    l.TextColor3 = T.sub
    return l
end

function Page:Picker()
    self.n = self.n + 1
    local holder = new("Frame", {Size = UDim2.new(1, 0, 0, 124), BackgroundColor3 = T.bg2, LayoutOrder = self.n}, self.Scroll)
    corner(holder, UDim.new(0, 20))
    stroke(holder, T.line, 1, 0.35)
    local info = new("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 16),
        Text = "Selected: -", TextColor3 = T.sub, Font = Enum.Font.GothamMedium, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left}, holder)
    local list = new("ScrollingFrame", {Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 1, -34), BackgroundTransparency = 1,
        ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, holder)
    new("UIListLayout", {Padding = UDim.new(0, 4)}, list)
    local buttons, picker = {}, {}
    function picker.paint()
        for p, b in pairs(buttons) do
            local sel = (Hub.Selected == p)
            tween(b.btn, .15, {BackgroundColor3 = sel and T.accent or T.bg3})
            b.txt.TextColor3 = sel and T.bg0 or T.text
            b.dot.BackgroundColor3 = RoleColor[getRole(p)]
        end
        info.Text = "Selected: " .. (Hub.Selected and Hub.Selected.DisplayName or "-")
    end
    function picker.refresh()
        if Hub.Selected and not Hub.Selected.Parent then Hub.Selected = nil end
        for p, b in pairs(buttons) do
            if not p.Parent then b.btn:Destroy() buttons[p] = nil end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and not buttons[p] then
                local btn = new("TextButton", {Size = UDim2.new(1, -4, 0, 26), BackgroundColor3 = T.bg3, Text = ""}, list)
                corner(btn)
                local dot = new("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 10, .5, 0),
                    Size = UDim2.fromOffset(8, 8), BackgroundColor3 = RoleColor.Innocent}, btn)
                corner(dot)
                local txt = new("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -34, 1, 0),
                    Text = p.DisplayName .. "  @" .. p.Name, TextColor3 = T.text, Font = Enum.Font.GothamMedium, TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, btn)
                btn.Activated:Connect(function()
                    Hub.Selected = p
                    for _, pk in ipairs(Hub.Pickers) do pk.paint() end
                end)
                buttons[p] = {btn = btn, txt = txt, dot = dot}
            end
        end
        picker.paint()
    end
    Hub.Pickers[#Hub.Pickers + 1] = picker
    picker.refresh()
end

local function newPage(name)
    local cg = new("CanvasGroup", {Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        GroupTransparency = 1, Visible = false}, PageHost)
    local sc = new("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.line, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y}, cg)
    new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, sc)
    new("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10)}, sc)
    local P = setmetatable({Name = name, Group = cg, Scroll = sc, n = 0}, Page)
    Pages[name] = P
    return P
end

local function showPage(name)
    if CurrentPage == name then return end
    local old = Pages[CurrentPage]
    CurrentPage = name
    for n, t in pairs(TabBtns) do
        local on = (n == name)
        tween(t.b, .2, {BackgroundTransparency = on and 0 or 1})
        tween(t.st, .2, {Transparency = on and 0.55 or 1})
        tween(t.tl, .2, {TextColor3 = on and T.text or T.sub})
    end
    if old then
        tween(old.Group, .15, {GroupTransparency = 1})
        task.delay(.16, function() if CurrentPage ~= old.Name then old.Group.Visible = false end end)
    end
    local P = Pages[name]
    P.Group.Visible = true
    P.Group.Position = UDim2.fromOffset(0, 14)
    P.Group.GroupTransparency = 1
    tween(P.Group, .28, {GroupTransparency = 0, Position = UDim2.new()})
end

-- page builders ---------------------------------------------------------
local Builders = {}

Builders.Combat = function(P)
    P:Section("ESP")
    P:Toggle("ESP", "ESP")
    P:Toggle("Highlight (chams)", "ESPChams")
    P:Toggle("Names", "ESPNames")
    P:Toggle("Role", "ESPRole")
    P:Toggle("Distance (meters)", "ESPDist")
    P:Toggle("Wall check (visible / behind wall)", "ESPWall")
    P:Toggle("Gun drop ESP", "ESPGun")
    P:Section("Aimbot")
    P:Toggle("Aimbot", "Aim", function() if Hub.AimBtnRefresh then Hub.AimBtnRefresh() end end)
    P:Choice("Mode", "AimMode", {"Button", "Always"}, function() if Hub.AimBtnRefresh then Hub.AimBtnRefresh() end end)
    P:Choice("Target", "AimTarget", {"Nearest", "Murderer", "Sheriff", "Innocent"})
    P:Choice("Aim part", "AimPart", {"Head", "Torso"})
    P:Slider("FOV", "AimFOV", 40, 400, 5)
    P:Slider("Snap speed", "AimSmooth", 0.05, 1, 0.01)
    P:Slider("Prediction", "AimPredict", 0, 0.3, 0.01)
    P:Toggle("Wall check", "AimWall")
    P:Toggle("Show FOV circle", "AimShowFOV")
    P:Section("Auto shoot / kill")
    P:Toggle("Auto-Shoot (sheriff → murder / murder → sheriff)", "AutoShoot")
    P:Button("Shoot murderer now", function()
        local m = playerByRole("Murderer")
        local r = m and hrp(m)
        if r then shootAt(r.Position + r.AssemblyLinearVelocity * 0.12) else notify("murderer не найден") end
    end)
    P:Button("Grab gun", grabGun)
    P:Toggle("Auto grab gun", "AutoGrab")
    P:Button("Kill all (murderer)", killAllOnce)
    P:Toggle("Loop kill all", "KillLoop")
    P:Button("Stop", function() Hub.Killing = false Cfg.KillLoop = false notify("stopped") end)
end

Builders.Fling = function(P)
    P:Picker()
    P:Button("Fling selected", function()
        if Hub.Selected then runFling({Hub.Selected}) else notify("выбери игрока") end
    end)
    P:Button("Fling sheriff", function()
        local p = playerByRole("Sheriff")
        if p then runFling({p}) else notify("sheriff не найден") end
    end)
    P:Button("Fling murderer", function()
        local p = playerByRole("Murderer")
        if p then runFling({p}) else notify("murderer не найден") end
    end)
    P:Button("Fling all", function() runFling(allOthers()) end)
    P:Button("Stop fling", function() Hub.StopFling = true end)
    P:Slider("Time per target (s)", "FlingTime", 1, 6, 0.5)
    P:Toggle("Cheater bypass (ротация частей тела)", "Bypass")
    P:Toggle("Anti-fling", "AntiFling")
end

Builders.Teleports = function(P)
    P:Picker()
    P:Button("Teleport to selected", function()
        if Hub.Selected then tpToPlayer(Hub.Selected) else notify("выбери игрока") end
    end)
    P:Button("Lobby", function()
        local cf = lobbyCF()
        if cf then tpTo(cf) else notify("лобби не найдено") end
    end)
    P:Button("Map", function()
        local cf = mapCF()
        if cf then tpTo(cf) else notify("карты нет (раунд не идёт)") end
    end)
    P:Button("To murderer", function()
        local p = playerByRole("Murderer")
        if p then tpToPlayer(p) else notify("murderer не найден") end
    end)
    P:Button("To sheriff", function()
        local p = playerByRole("Sheriff")
        if p then tpToPlayer(p) else notify("sheriff не найден") end
    end)
    P:Button("To gun drop", function()
        local gd = Workspace:FindFirstChild("GunDrop")
        if gd then tpTo((gd:IsA("BasePart") and gd.CFrame or gd:GetPivot()) + Vector3.new(0, 3, 0)) else notify("GunDrop нет") end
    end)
    P:Button("Save position", function()
        local r = hrp(LP)
        if r then SavedPos = r.CFrame notify("позиция сохранена") end
    end)
    P:Button("Return to saved", function()
        if SavedPos then tpTo(SavedPos) else notify("нет сохранённой позиции") end
    end)
end

Builders.AutoFarm = function(P)
    P:Toggle("Auto farm coins", "AutoFarm", function(v)
        if not v then Hub.ForceNoclip = false farmStatus("Off") end
    end)
    P:Slider("Tween speed", "FarmSpeed", 16, 80, 1)
    P:Slider("Bag size", "BagMax", 10, 60, 1)
    P:Toggle("Reset when bag is full", "FarmReset")
    FarmLabel = P:Label("Off")
end

local Boom_ID = ""
Builders.Player = function(P)
    P:Section("Movement")
    P:Toggle("Speed", "Speed")
    P:Slider("Walk speed", "SpeedVal", 16, 150, 1)
    P:Toggle("Jump", "Jump")
    P:Slider("Jump power", "JumpVal", 50, 250, 1)
    P:Toggle("Infinite jump", "InfJump")
    P:Toggle("Fly", "Fly", function(v)
        if v then startFly() else stopFly() end
        if Hub.FlyBtnRefresh then Hub.FlyBtnRefresh() end
    end)
    P:Slider("Fly speed", "FlySpeed", 20, 200, 1)
    P:Toggle("Noclip", "Noclip")
    P:Section("Avatar (client-side)")
    P:Toggle("Fake headless", "Headless", function(v) applyHeadless(v) end)
    P:Toggle("Fake korblox", "Korblox", function(v) applyKorblox(v) end)
    P:Section("Boombox (local)")
    P:Input("Audio ID", "rbxassetid", function(t) Boom_ID = t end)
    P:Button("Play", function() boomPlay(Boom_ID) end)
    P:Button("Stop", function() Boom:Stop() end)
    P:Slider("Volume", "BoomVol", 0, 5, 0.1, function(v) Boom.Volume = v end)
end

local function Unload() end -- заполняется ниже

Builders.Settings = function(P)
    P:Toggle("Notifications", "Notify")
    P:Toggle("Anti-AFK", "AntiAFK")
    P:Button("Rejoin server", function() TeleportService:Teleport(game.PlaceId, LP) end)
    P:Button("Unload EntezHub", function() Unload() end)
    P:Label("PC: RightShift — свернуть / развернуть")
end

Builders["UI Custom"] = function(P)
    P:Section("Accent")
    local r = P:Row(44)
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
        VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Center}, r)
    local swatches = {
        Color3.fromRGB(235, 235, 240), Color3.fromRGB(120, 190, 255), Color3.fromRGB(255, 80, 90),
        Color3.fromRGB(90, 235, 160), Color3.fromRGB(170, 120, 255), Color3.fromRGB(255, 190, 80),
    }
    for _, c in ipairs(swatches) do
        local b = new("TextButton", {Size = UDim2.fromOffset(26, 26), BackgroundColor3 = c, Text = ""}, r)
        corner(b)
        stroke(b, T.line, 1, 0.2)
        b.Activated:Connect(function() setAccent(c) end)
        pressFx(b, b)
    end
    P:Section("Window")
    P:Slider("UI scale", "UIScale", 0.6, 1.3, 0.05, function()
        if WinScale and not minimized then tween(WinScale, .15, {Scale = targetScale()}) end
    end)
    P:Button("Reset window position", function()
        if Main then tween(Main, .3, {Position = UDim2.fromScale(.5, .5)}) end
    end)
end

------------------------------------------------------------------ floating buttons (aim / fly)
local function floatBtn(iconName, pos)
    local b = new("TextButton", {AnchorPoint = Vector2.new(1, .5), Position = pos, Size = UDim2.fromOffset(50, 50),
        BackgroundColor3 = T.bg0, Text = "", Visible = false}, Gui)
    corner(b)
    stroke(b, T.line, 1.2)
    local ic = icon(iconName, 24)
    ic.AnchorPoint = Vector2.new(.5, .5)
    ic.Position = UDim2.fromScale(.5, .5)
    ic.Parent = b
    pressFx(b, b)
    return b
end
local AimBtn = floatBtn("Combat", UDim2.new(1, -80, .55, 0))
local UpBtn = floatBtn("Up", UDim2.new(1, -150, .42, 0))
local DownBtn = floatBtn("Down", UDim2.new(1, -150, .68, 0))
local function holdBtn(b, onDown, onUp)
    b.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then onDown() end
    end)
    b.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then onUp() end
    end)
end
holdBtn(AimBtn, function() AimHeld = true tween(AimBtn, .1, {BackgroundColor3 = T.bg3}) end,
    function() AimHeld = false tween(AimBtn, .15, {BackgroundColor3 = T.bg0}) end)
holdBtn(UpBtn, function() Hub.FlyV = 1 end, function() if Hub.FlyV == 1 then Hub.FlyV = 0 end end)
holdBtn(DownBtn, function() Hub.FlyV = -1 end, function() if Hub.FlyV == -1 then Hub.FlyV = 0 end end)
Hub.AimBtnRefresh = function() AimBtn.Visible = Cfg.Aim and Cfg.AimMode == "Button" and not minimized end
Hub.FlyBtnRefresh = function() UpBtn.Visible = Cfg.Fly and not minimized DownBtn.Visible = Cfg.Fly and not minimized end

local FOVRing = new("Frame", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), BackgroundTransparency = 1, Visible = false}, Gui)
corner(FOVRing)
stroke(FOVRing, Color3.new(1, 1, 1), 1.5, 0.35)
track(RunService.RenderStepped:Connect(function()
    local show = Cfg.Aim and Cfg.AimShowFOV
    FOVRing.Visible = show
    if show then FOVRing.Size = UDim2.fromOffset(Cfg.AimFOV * 2, Cfg.AimFOV * 2) end
end))

------------------------------------------------------------------ unload
Unload = function()
    if not Hub.Alive then return end
    Hub.Alive = false
    Hub.StopFling, Hub.Killing = true, false
    Cfg.Fly = false
    pcall(stopFly)
    pcall(function() applyHeadless(false) end)
    pcall(function() applyKorblox(false) end)
    pcall(function()
        local h = hum(LP)
        if h then h.WalkSpeed = 16 h.UseJumpPower = true h.JumpPower = 50 end
    end)
    for _, c in ipairs(Hub.Conns) do pcall(function() c:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("EntezAim") end)
    pcall(function() Boom:Destroy() end)
    pcall(function() ESPFolder:Destroy() end)
    if WinScale then tween(WinScale, .25, {Scale = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.In) end
    task.delay(.3, function() pcall(function() Gui:Destroy() end) end)
    env.EntezHubUnload = nil
end
env.EntezHubUnload = Unload

------------------------------------------------------------------ loader + window
task.spawn(function()
    -- loader
    local Loader = new("Frame", {Name = "Loader", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromOffset(270, 176), BackgroundColor3 = T.bg0}, Gui)
    corner(Loader, UDim.new(0, 26))
    stroke(Loader, T.line, 1.2)
    local LScale = new("UIScale", {Scale = 0}, Loader)
    tween(LScale, .45, {Scale = 1}, Enum.EasingStyle.Back)
    local ring = new("Frame", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 22), Size = UDim2.fromOffset(46, 46),
        BackgroundTransparency = 1}, Loader)
    corner(ring)
    local rs = new("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, ring)
    local grad = new("UIGradient", {Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.5, 0), NumberSequenceKeypoint.new(1, 1)})}, rs)
    new("TextLabel", {AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromOffset(30, 30),
        BackgroundTransparency = 1, Text = "E", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 20}, ring)
    new("TextLabel", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 80), Size = UDim2.fromOffset(220, 26),
        BackgroundTransparency = 1, Text = "EntezHub", TextColor3 = T.text, Font = Enum.Font.GothamBold, TextSize = 22}, Loader)
    local status = new("TextLabel", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 110), Size = UDim2.fromOffset(220, 16),
        BackgroundTransparency = 1, Text = "Initializing", TextColor3 = T.sub, Font = Enum.Font.GothamMedium, TextSize = 11}, Loader)
    local pbar = new("Frame", {AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 140), Size = UDim2.fromOffset(200, 6),
        BackgroundColor3 = T.bg3}, Loader)
    corner(pbar)
    local pfill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1)}, pbar)
    corner(pfill)
    local spin = RunService.RenderStepped:Connect(function(dt) grad.Rotation = (grad.Rotation + 320 * dt) % 360 end)
    local function setProgress(a, text)
        status.Text = text
        tween(pfill, .3, {Size = UDim2.fromScale(a, 1)})
    end
    task.wait(0.5)
    setProgress(0.12, "Building interface")

    -- main window
    Main = new("Frame", {Name = "Main", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromOffset(540, 320), BackgroundColor3 = T.bg0, Visible = false}, Gui)
    corner(Main, UDim.new(0, 26))
    stroke(Main, T.line, 1.2)
    WinScale = new("UIScale", {Scale = 0}, Main)

    local Top = new("Frame", {Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(524, 40), BackgroundColor3 = T.bg1}, Main)
    corner(Top, UDim.new(0, 20))
    local logo = new("Frame", {AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 10, .5, 0), Size = UDim2.fromOffset(24, 24),
        BackgroundColor3 = Color3.new(1, 1, 1)}, Top)
    corner(logo)
    new("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "E", TextColor3 = T.bg0,
        Font = Enum.Font.GothamBold, TextSize = 15}, logo)
    new("TextLabel", {Position = UDim2.fromOffset(44, 3), Size = UDim2.fromOffset(160, 18), BackgroundTransparency = 1, Text = "EntezHub",
        TextColor3 = T.text, Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left}, Top)
    new("TextLabel", {Position = UDim2.fromOffset(44, 21), Size = UDim2.fromOffset(160, 14), BackgroundTransparency = 1, Text = "Murder Mystery 2",
        TextColor3 = T.sub, Font = Enum.Font.GothamMedium, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left}, Top)

    local function ctlBtn(iconName, xOff)
        local b = new("TextButton", {AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, xOff, .5, 0), Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = T.bg3, Text = ""}, Top)
        corner(b)
        local ic = icon(iconName, 14)
        ic.AnchorPoint = Vector2.new(.5, .5)
        ic.Position = UDim2.fromScale(.5, .5)
        ic.Parent = b
        b.MouseEnter:Connect(function() tween(b, .15, {BackgroundColor3 = T.line}) end)
        b.MouseLeave:Connect(function() tween(b, .15, {BackgroundColor3 = T.bg3}) end)
        pressFx(b, b)
        return b
    end
    local CloseB = ctlBtn("Close", -10)
    local MinB = ctlBtn("Minimize", -44)

    Top.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            local sm = Vector2.new(i.Position.X, i.Position.Y)
            local sp = Main.Position
            beginDrag(i, function(pos)
                local d = (Vector2.new(pos.X, pos.Y) - sm) / math.max(WinScale.Scale, 0.05)
                Main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
            end)
        end
    end)

    local Side = new("ScrollingFrame", {Position = UDim2.fromOffset(8, 56), Size = UDim2.fromOffset(140, 256), BackgroundColor3 = T.bg1,
        ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, Main)
    corner(Side, UDim.new(0, 20))
    new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, Side)
    new("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, Side)

    local Content = new("Frame", {Position = UDim2.fromOffset(156, 56), Size = UDim2.fromOffset(376, 256), BackgroundColor3 = T.bg1}, Main)
    corner(Content, UDim.new(0, 20))
    PageHost = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true}, Content)

    setProgress(0.25, "Loading icons")
    for i, name in ipairs(Names) do
        local b = new("TextButton", {Name = name, Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.bg3, BackgroundTransparency = 1,
            Text = "", LayoutOrder = i}, Side)
        corner(b)
        local st = stroke(b, T.accent, 1, 1)
        local ic = icon(name, 16)
        ic.Position = UDim2.fromOffset(11, 7)
        ic.Parent = b
        local tl = new("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -40, 1, 0),
            Text = name, TextColor3 = T.sub, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left}, b)
        TabBtns[name] = {b = b, st = st, tl = tl}
        b.Activated:Connect(function() showPage(name) end)
        pressFx(b, b)
        task.wait(0.05)
    end
    onAccent(function(c) for _, t in pairs(TabBtns) do t.st.Color = c end end)

    for i, name in ipairs(Names) do
        setProgress(0.3 + 0.6 * i / #Names, "Loading " .. name)
        local ok, err = pcall(function() Builders[name](newPage(name)) end)
        if not ok then warn("[EntezHub] " .. name .. ": " .. tostring(err)) end
        task.wait(0.14)
    end

    -- mini button
    Mini = new("TextButton", {Position = UDim2.fromOffset(24, 90), Size = UDim2.fromOffset(48, 48), BackgroundColor3 = T.bg0,
        Text = "E", TextColor3 = T.text, Font = Enum.Font.GothamBold, TextSize = 20, Visible = false}, Gui)
    corner(Mini)
    stroke(Mini, T.line, 1.4)
    MiniScale = new("UIScale", {Scale = 0}, Mini)

    local function setMin(v)
        minimized = v
        if v then
            tween(WinScale, .25, {Scale = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
            task.delay(.26, function() if minimized then Main.Visible = false end end)
            Mini.Visible = true
            tween(MiniScale, .3, {Scale = 1}, Enum.EasingStyle.Back)
        else
            Main.Visible = true
            tween(MiniScale, .2, {Scale = 0})
            task.delay(.21, function() if not minimized then Mini.Visible = false end end)
            tween(WinScale, .32, {Scale = targetScale()}, Enum.EasingStyle.Back)
        end
        Hub.AimBtnRefresh()
        Hub.FlyBtnRefresh()
    end
    MinB.Activated:Connect(function() setMin(true) end)
    CloseB.Activated:Connect(function() Unload() end)
    Mini.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            local sm = Vector2.new(i.Position.X, i.Position.Y)
            local sp = Mini.Position
            local moved = 0
            beginDrag(i, function(pos)
                local d = Vector2.new(pos.X, pos.Y) - sm
                moved = math.max(moved, d.Magnitude)
                Mini.Position = UDim2.fromOffset(sp.X.Offset + d.X, sp.Y.Offset + d.Y)
            end, function() if moved < 8 then setMin(false) end end)
        end
    end)
    track(UIS.InputBegan:Connect(function(i, gp)
        if not gp and i.KeyCode == Cfg.ToggleKey then setMin(not minimized) end
    end))

    setProgress(1, "Ready")
    task.wait(0.5)
    spin:Disconnect()
    tween(LScale, .3, {Scale = 0}, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.wait(0.3)
    Loader:Destroy()

    Main.Visible = true
    tween(WinScale, .45, {Scale = targetScale()}, Enum.EasingStyle.Back)
    showPage("Combat")
    notify("EntezHub loaded")

    task.spawn(function()
        while Hub.Alive do
            task.wait(1.5)
            for _, pk in ipairs(Hub.Pickers) do pcall(pk.refresh) end
        end
    end)
end)
