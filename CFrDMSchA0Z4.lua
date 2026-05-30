-- SAKIWARE | Two-Time Standalone
-- maintained by mitsuki

local svc = {
    Players      = game:GetService("Players"),
    Run          = game:GetService("RunService"),
    RS           = game:GetService("ReplicatedStorage"),
    WS           = game:GetService("Workspace"),
}

local lp      = svc.Players.LocalPlayer
local Event   = svc.RS.Modules.Network.Network.RemoteEvent

-- Settings
local S = {
    enabled      = false,
    range        = 15,
    showCircle   = true,
    circleColor  = Color3.fromRGB(255, 100, 200),
}

------------------------------------------------------------------------
-- WindUI
------------------------------------------------------------------------
local ui = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

local win = ui:CreateWindow({
    Title            = "Two-Time",
    Icon             = "zap",
    Author           = "mitsuki",
    Folder           = "SAKIWARE",
    Size             = UDim2.fromOffset(350, 280),
    Transparent      = false,
    Theme            = "Dark",
    Resizable        = false,
    SideBarWidth     = 150,
    HideSearchBar    = true,
    ScrollBarEnabled = false,
})

win:SetToggleKey(Enum.KeyCode.L)

local tab = win:Tab({ Title = "Two-Time", Icon = "zap" })
local sec = tab:Section({ Title = "Dagger Config", Opened = true })

sec:Toggle({
    Title   = "Enabled",
    Default = false,
    Callback = function(v) S.enabled = v end,
})

sec:Slider({
    Title   = "Range (studs)",
    Min     = 5,
    Max     = 50,
    Default = 15,
    Callback = function(v) S.range = v end,
})

sec:Toggle({
    Title   = "Show Circle",
    Default = true,
    Callback = function(v)
        S.showCircle = v
        if not v then
            for _, c in pairs(circles) do
                pcall(function() c:Destroy() end)
            end
            circles = {}
        end
    end,
})

sec:Slider({
    Title   = "Lunge Hold (ms)",
    Min     = 50,
    Max     = 1000,
    Default = 250,
    Callback = function(v) LUNGE_HOLD_DURATION = v / 1000 end,
})

-- How long to hold HRP rotation lock after dagger fires (wired to slider)
local LUNGE_HOLD_DURATION = 0.25

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function getKillersFolder()
    local p = svc.WS:FindFirstChild("Players")
    return p and p:FindFirstChild("Killers")
end

local function getNearestKiller()
    local myChar = lp.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil, nil end

    local kf = getKillersFolder()
    if not kf then return nil, nil end

    local closest, closestHRP, closestDist = nil, nil, math.huge
    for _, k in pairs(kf:GetChildren()) do
        local hrp = k:FindFirstChild("HumanoidRootPart")
        if hrp then
            local dist = (hrp.Position - myHRP.Position).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest     = k
                closestHRP  = hrp
            end
        end
    end
    return closest, closestHRP, closestDist
end

------------------------------------------------------------------------
-- Detection Circles (on killer HRP)
------------------------------------------------------------------------
circles = {}

local function updateCircles()
    local kf = getKillersFolder()
    if not kf then return end

    for _, k in pairs(kf:GetChildren()) do
        local hrp = k:FindFirstChild("HumanoidRootPart")
        if hrp then
            if S.showCircle and S.enabled then
                if not circles[k] then
                    pcall(function()
                        local c = Instance.new("CylinderHandleAdornment")
                        c.Name        = "TwoTimeCircle"
                        c.Adornee     = hrp
                        c.Color3      = S.circleColor
                        c.AlwaysOnTop = true
                        c.ZIndex      = 1
                        c.Transparency = 0.5
                        c.Radius      = S.range
                        c.Height      = 0.12
                        c.CFrame      = CFrame.new(0, -(hrp.Size.Y / 2 + 0.05), 0) * CFrame.Angles(math.rad(90), 0, 0)
                        c.Parent      = hrp
                        circles[k]    = c
                    end)
                else
                    circles[k].Radius = S.range
                end
            else
                if circles[k] then
                    pcall(function() circles[k]:Destroy() end)
                    circles[k] = nil
                end
            end
        end
    end

    -- Cleanup dead killers
    for k, c in pairs(circles) do
        if not k.Parent or not k:FindFirstChild("HumanoidRootPart") then
            pcall(function() c:Destroy() end)
            circles[k] = nil
        end
    end
end

------------------------------------------------------------------------
-- Fire abilities
------------------------------------------------------------------------
local function fireCrouch()
    firesignal(Event.OnClientEvent,
        "UseActorAbility",
        { buffer.fromstring("\x03\x06\x00\x00\x00Crouch") }
    )
end

local function fireDagger()
    firesignal(Event.OnClientEvent,
        "UseActorAbility",
        { buffer.fromstring("\x03\x06\x00\x00\x00Dagger") }
    )
end

local activeFlip = false

local function flipToKillerBack(killerModel)
    if activeFlip then return end
    activeFlip = true

    local holdStart = os.clock()
    local holdConn
    holdConn = svc.Run.Heartbeat:Connect(function()
        if os.clock() - holdStart >= LUNGE_HOLD_DURATION then
            holdConn:Disconnect()
            activeFlip = false
            return
        end

        local char = lp.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local khrp = killerModel and killerModel:FindFirstChild("HumanoidRootPart")
        if not hrp or not khrp then
            holdConn:Disconnect()
            activeFlip = false
            return
        end

        -- Lock HRP to face same direction as killer every frame
        local look = khrp.CFrame.LookVector
        hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + look, Vector3.new(0, 1, 0))
    end)
end

------------------------------------------------------------------------
-- Hook: intercept OnClientEvent for Crouch
------------------------------------------------------------------------
local crouchConn = nil

local function hookCrouch()
    if crouchConn then crouchConn:Disconnect(); crouchConn = nil end

    crouchConn = Event.OnClientEvent:Connect(function(action, data)
        if not S.enabled then return end
        if action ~= "UseActorAbility" then return end

        -- Check if this is a Crouch signal
        local isCrouch = false
        if type(data) == "table" then
            for _, v in ipairs(data) do
                if typeof(v) == "buffer" then
                    local str = buffer.tostring(v)
                    if str:find("Crouch") then
                        isCrouch = true
                        break
                    end
                end
            end
        end

        if not isCrouch then return end

        -- Check killer is in range
        local killer, killerHRP, dist = getNearestKiller()
        if not killer or dist > S.range then return end

        task.spawn(function()
            -- Fire dagger + start HRP lock at the same time
            fireDagger()
            flipToKillerBack(killer)
        end)
    end)
end

hookCrouch()

------------------------------------------------------------------------
-- Visual loop
------------------------------------------------------------------------
svc.Run.Heartbeat:Connect(function()
    updateCircles()
end)
