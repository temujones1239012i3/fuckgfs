local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer


--// ===========================
--// AUTO START ALL MODULES
--// ===========================
task.defer(function()
    repeat task.wait() until ScriptModules  -- wait until ScriptModules is loaded
    for name, module in pairs(ScriptModules) do
        if type(module) == "table" and type(module.init) == "function" then
            local ok, err = pcall(function()
                module:init()
            end)
            if ok then
                module.active = true
                print("[Vster Hub] ✅ Auto-started:", module.name or name)
            else
                warn("[Vster Hub] ⚠️ Failed to start module:", name, err)
            end
        end
    end
end)

-- =======================
-- SETTINGS PERSISTENCE - INSTANT LOAD (DELTA/VOLCANO)
-- =======================
local SETTINGS_KEY = "VsterHub_Settings_" .. tostring(game.PlaceId)

-- Shared global storage for instant access
if not shared.VsterHubSettings then
    shared.VsterHubSettings = {}
end

-- Try multiple file operation methods
local function getWriteFile()
    return writefile or write_file or (syn and syn.write_file)
end

local function getReadFile()
    return readfile or read_file or (syn and syn.read_file)
end

local function getIsFile()
    return isfile or is_file or (syn and syn.is_file)
end

local function saveSettings()
    if not ScriptModules then return end
    
    -- Save to shared immediately
    local settings = {}
    for key, module in pairs(ScriptModules) do
        settings[key] = module.active
    end
    shared.VsterHubSettings[SETTINGS_KEY] = settings
    
    -- Also save to file for cross-session persistence
    task.spawn(function()
        local writeFunc = getWriteFile()
        if writeFunc then
            pcall(function()
                writeFunc(SETTINGS_KEY .. ".txt", HttpService:JSONEncode(settings))
            end)
        end
    end)
end

local function loadSettings()
    if not ScriptModules then 
        warn("[Vster Hub] ScriptModules not initialized yet")
        return false 
    end
    
    local settings = nil
    
    -- Method 1: Check shared memory (instant, works across script reloads)
    if shared.VsterHubSettings[SETTINGS_KEY] then
        settings = shared.VsterHubSettings[SETTINGS_KEY]
        print("[Vster Hub] ✓ Loaded from memory (instant)")
    else
        -- Method 2: Try file system
        local readFunc = getReadFile()
        local isFileFunc = getIsFile()
        
        if readFunc and isFileFunc then
            local success, result = pcall(function()
                if isFileFunc(SETTINGS_KEY .. ".txt") then
                    local data = readFunc(SETTINGS_KEY .. ".txt")
                    return HttpService:JSONDecode(data)
                end
                return nil
            end)
            
            if success and result then
                settings = result
                shared.VsterHubSettings[SETTINGS_KEY] = settings
                print("[Vster Hub] ✓ Loaded from file")
            end
        end
    end
    
    -- Apply settings immediately
    if settings and type(settings) == "table" then
        for key, active in pairs(settings) do
            if ScriptModules[key] then
                ScriptModules[key].active = active
                if active then
                    task.spawn(function()
                        pcall(function()
                            ScriptModules[key]:init()
                        end)
                    end)
                end
            end
        end
        return true
    end
    
    return false
end


-- =======================
-- AUTO-RELOAD (VOLCANO + DELTA + SYNAPSE + KRNL)
-- =======================
local ADMIN_RAW_URL = "https://raw.githubusercontent.com/temujones1239012i3/11234123123/refs/heads/main/hub1.lua"

local function setupAutoReload()
    if shared._VsterAutoReloadQueued then
        warn("[Vster Hub] Auto-reload already queued this session.")
        return
    end
    shared._VsterAutoReloadQueued = true

    -- === Find a compatible queue_on_teleport ===
    local function findQueueFunc()
        local candidates = {
            queue_on_teleport,
            queueonteleport,
            (syn and syn.queue_on_teleport),
            (KRNL and KRNL.queue_on_teleport),
            (getgenv and getgenv().queue_on_teleport),
            (getgenv and getgenv().queueonteleport),
            _G.queue_on_teleport,
            _G.queueonteleport,
        }

        for _, fn in ipairs(candidates) do
            if type(fn) == "function" then
                return fn
            end
        end

        -- Deep search (for obfuscated executors)
        for k, v in pairs(_G) do
            if type(v) == "function" and tostring(k):lower():find("teleport") then
                return v
            end
        end
        for k, v in pairs(getgenv()) do
            if type(v) == "function" and tostring(k):lower():find("teleport") then
                return v
            end
        end
        return nil
    end

    local queueFunc = findQueueFunc()
    if not queueFunc then
        warn("[Vster Hub] No queue_on_teleport function found! Volcano may need global env.")
        return
    end

    local payload = string.format([[
        task.wait(0.5)
        local url = "%s"

        local function safeGet(u)
            local ok, res

            ok, res = pcall(function() return game:HttpGet(u) end)
            if ok and res then return res end

            if type(http_request) == "function" then
                ok, res = pcall(function() return http_request({Url=u, Method="GET"}).Body end)
                if ok and res then return res end
            end

            if type(request) == "function" then
                ok, res = pcall(function() return request({Url=u, Method="GET"}).Body end)
                if ok and res then return res end
            end

            if syn and type(syn.request) == "function" then
                ok, res = pcall(function() return syn.request({Url=u, Method="GET"}).Body end)
                if ok and res then return res end
            end

            local HttpService = game:GetService("HttpService")
            ok, res = pcall(function() return HttpService:GetAsync(u) end)
            if ok and res then return res end

            return nil
        end

        local code = safeGet(url)
        if code then
            local fn, err = loadstring(code)
            if fn then
                local success, execErr = pcall(fn)
                if success then
                    print("[Vster Hub] ✓ Auto-reloaded after teleport!")
                else
                    warn("[Vster Hub] Runtime error:", execErr)
                end
            else
                warn("[Vster Hub] Failed to compile:", err)
            end
        else
            warn("[Vster Hub] Could not fetch script from GitHub.")
        end
    ]], ADMIN_RAW_URL)

    local ok, err = pcall(function()
        queueFunc(payload)
    end)

    if ok then
        print("[Vster Hub] ✓ Auto-reload queued successfully (Volcano compatible).")
    else
        warn("[Vster Hub] Failed to queue auto-reload:", err)
    end
end

setupAutoReload()

-- =======================
-- SCRIPT STORAGE
-- =======================

local ScriptModules = {}


-- Each module has: name, category, init (function to start), cleanup (function to stop), active (boolean), and stored data
ScriptModules["PetTracker"] = {
    name = "Brainrot ESP",
    category = "ESP",
    active = true,
    data = {},
    
    init = function(self)
        -- CONFIG
        local VALUE_THRESHOLD = 5e6
        local WHITELIST_NAMES = {"Graipuss Medussi", "Nooo My Hotspot", "La Sahur Combinasion", "Pot Hotspot", "Chicleteira Bicicleteira"}
        
        -- Helpers
        local function parseMoney(text)
            text = string.lower(text or "")
            local num = tonumber(text:match("[%d%.]+")) or 0
            if text:find("k") then num *= 1e3
            elseif text:find("m") then num *= 1e6
            elseif text:find("b") then num *= 1e9
            elseif text:find("t") then num *= 1e12 end
            return num
        end
        
        local function abbreviate(n)
            local abs = math.abs(n)
            if abs >= 1e12 then return string.format("%.2ft", n/1e12):gsub("%.0t","t") end
            if abs >= 1e9 then return string.format("%.2fb", n/1e9):gsub("%.0b","b") end
            if abs >= 1e6 then return string.format("%.2fm", n/1e6):gsub("%.0m","m") end
            if abs >= 1e3 then return string.format("%.2fk", n/1e3):gsub("%.0k","k") end
            return tostring(math.floor(n))
        end
        
        local function isBlacklisted(obj)
            while obj do
                local name = string.lower(obj.Name or "")
                if name == "generationboard" or name:find("top") then return true end
                obj = obj.Parent
            end
            return false
        end
        
        local function findMainName(billboard)
            local bestText, bestLen
            for _, d in ipairs(billboard:GetDescendants()) do
                if d:IsA("TextLabel") then
                    local t = d.Text or ""
                    if not t:find("/s") and not t:find("%$") then
                        if not bestLen or #t > bestLen then bestText, bestLen = t, #t end
                    end
                end
            end
            return bestText
        end
        
        local function isLuckyBlock(billboard)
            local sawLucky, sawSecret = false, false
            for _, d in ipairs(billboard:GetDescendants()) do
                if d:IsA("TextLabel") then
                    local t = string.lower(d.Text or "")
                    if t:find("lucky block") then sawLucky = true end
                    if t:find("secret") then sawSecret = true end
                end
            end
            return sawLucky and sawSecret
        end
        
        local function getModelForLabel(label)
            local bb = label:FindFirstAncestorWhichIsA("BillboardGui")
            if bb then
                if bb.Adornee and bb.Adornee:IsA("BasePart") then
                    local m = bb.Adornee:FindFirstAncestorWhichIsA("Model")
                    if m then return m end
                end
                if bb.Parent and bb.Parent:IsA("Model") then return bb.Parent end
            end
            return label:FindFirstAncestorWhichIsA("Model")
        end
        
        local function getAnyPart(model)
            if not model then return nil end
            return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
        end
        
        self.data.tracked = {}
        
        local function clearVisuals(model)
            if self.data.tracked[model] then
                for _, v in ipairs(self.data.tracked[model]) do
                    if v and v.Destroy then pcall(function() v:Destroy() end) end
                end
                self.data.tracked[model] = nil
            end
        end
        
        local function setVisuals(model, part, name, value, kind)
            clearVisuals(model)
            local highlight = Instance.new("Highlight")
            highlight.Name = "PetHighlight_Client"
            if kind == "top" then
                highlight.FillColor = Color3.fromRGB(0,255,0)
            elseif kind == "whitelist" then
                highlight.FillColor = Color3.fromRGB(0,128,255)
            elseif kind == "lucky" then
                highlight.FillColor = Color3.fromRGB(180,0,255)
            else
                highlight.FillColor = Color3.fromRGB(255,215,0)
            end
            highlight.OutlineColor = Color3.fromRGB(255,255,255)
            highlight.FillTransparency = 0.5
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Adornee = model
            highlight.Parent = model
            
            local billboardGui = Instance.new("BillboardGui")
            billboardGui.Name = "PetBillboard_Client"
            billboardGui.Adornee = part
            billboardGui.Size = UDim2.new(0, 240, 0, (kind == "threshold") and 30 or 60)
            billboardGui.StudsOffset = Vector3.new(0, 6, 0)
            billboardGui.AlwaysOnTop = true
            billboardGui.MaxDistance = 1e6
            billboardGui.Parent = player:WaitForChild("PlayerGui")
            
            local textLabel = Instance.new("TextLabel")
            textLabel.Size = UDim2.new(1, 0, 1, 0)
            textLabel.BackgroundTransparency = 1
            textLabel.Font = Enum.Font.SourceSansBold
            textLabel.TextScaled = true
            textLabel.TextStrokeTransparency = 0
            textLabel.TextColor3 = highlight.FillColor
            textLabel.Parent = billboardGui
            
            if kind == "lucky" then
                textLabel.Text = "Lucky Block (Secret!)"
            elseif value then
                textLabel.Text = string.format("%s | $%s/s", name, abbreviate(value))
            else
                textLabel.Text = name
            end
            
            self.data.tracked[model] = {highlight, billboardGui, textLabel}
        end
        
        local function updateBest()
            if not self.active then return end
            
            local bestLabel, bestValue = nil, -math.huge
            local extraList = {}
            
            for _, bb in ipairs(workspace:GetDescendants()) do
                if bb:IsA("BillboardGui") and not isBlacklisted(bb) then
                    if isLuckyBlock(bb) then
                        local model = bb:FindFirstAncestorWhichIsA("Model")
                        local part = getAnyPart(model)
                        if model and part then
                            table.insert(extraList, {model, part, "Lucky Block", nil, "lucky"})
                        end
                    end
                    
                    for _, lbl in ipairs(bb:GetDescendants()) do
                        if lbl:IsA("TextLabel") then
                            local text = lbl.Text or ""
                            if text:find("/s") and text:find("%$") then
                                local val = parseMoney(text)
                                local model = getModelForLabel(lbl)
                                local part = getAnyPart(model)
                                if model and part then
                                    if val > bestValue then
                                        bestValue = val
                                        bestLabel = lbl
                                    end
                                    
                                    local petName = findMainName(bb) or model.Name
                                    for _, w in ipairs(WHITELIST_NAMES) do
                                        if petName == w then
                                            table.insert(extraList, {model, part, petName, val, "whitelist"})
                                        end
                                    end
                                    
                                    if val >= VALUE_THRESHOLD then
                                        local petName = findMainName(bb) or model.Name
                                        table.insert(extraList, {model, part, petName, val, "threshold"})
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            for model in pairs(self.data.tracked) do
                clearVisuals(model)
            end
            
            if bestLabel then
                local model = getModelForLabel(bestLabel)
                local part = getAnyPart(model)
                if model and part then
                    local petName = findMainName(bestLabel:FindFirstAncestorWhichIsA("BillboardGui")) or model.Name
                    setVisuals(model, part, petName, bestValue, "top")
                end
            end
            
            for _, entry in ipairs(extraList) do
                local model, part, name, val, kind = unpack(entry)
                if model and part and not self.data.tracked[model] then
                    setVisuals(model, part, name, val, kind)
                end
            end
        end
        
        self.data.updateLoop = task.spawn(function()
            while self.active do
                updateBest()
                task.wait(1)
            end
        end)
    end,
    
    cleanup = function(self)
        if self.data.tracked then
            for model, objs in pairs(self.data.tracked) do
                for _, obj in ipairs(objs) do
                    if obj and obj.Destroy then pcall(function() obj:Destroy() end) end
                end
            end
            self.data.tracked = {}
        end
        if self.data.updateLoop then
            task.cancel(self.data.updateLoop)
            self.data.updateLoop = nil
        end
    end
}

ScriptModules["PlayerESP"] = {
    name = "Player ESP",
    category = "ESP",
    active = true,
    data = {},
    
    init = function(self)
        self.data.visuals = {}
        self.data.connections = {}
        local BOX_COLOR = Color3.fromRGB(0, 200, 200)
        local NAME_COLOR = Color3.fromRGB(100, 200, 255)
        local BOX_TRANSPARENCY = 0.2
        
        local function addVisuals(target)
            if self.data.visuals[target] then return end
            if target == player then return end
            
            local function setup(char)
                if not char then return end
                if not self.active then return end
                
                if self.data.visuals[target] then
                    for _, obj in ipairs(self.data.visuals[target]) do
                        if obj and obj.Parent then pcall(function() obj:Destroy() end) end
                    end
                end
                
                local added = {}
                local box = Instance.new("SelectionBox")
                box.Name = "PlayerBox"
                box.Adornee = char
                box.LineThickness = 0.08
                box.Color3 = BOX_COLOR
                box.SurfaceTransparency = BOX_TRANSPARENCY
                box.Transparency = BOX_TRANSPARENCY
                box.Parent = char
                table.insert(added, box)
                
                local head = char:FindFirstChild("Head")
                if head then
                    local billboard = Instance.new("BillboardGui")
                    billboard.Name = "PlayerNameTag"
                    billboard.Adornee = head
                    billboard.Size = UDim2.new(0, 150, 0, 30)
                    billboard.StudsOffset = Vector3.new(0, 3, 0)
                    billboard.AlwaysOnTop = true
                    billboard.Parent = char
                    
                    local nameLabel = Instance.new("TextLabel")
                    nameLabel.Size = UDim2.new(1, 0, 1, 0)
                    nameLabel.BackgroundTransparency = 1
                    nameLabel.Text = target.DisplayName or target.Name
                    nameLabel.TextColor3 = NAME_COLOR
                    nameLabel.Font = Enum.Font.SourceSansBold
                    nameLabel.TextSize = 18
                    nameLabel.TextStrokeTransparency = 0.3
                    nameLabel.Parent = billboard
                    
                    table.insert(added, billboard)
                end
                
                self.data.visuals[target] = added
            end
            
            setup(target.Character)
            table.insert(self.data.connections, target.CharacterAdded:Connect(setup))
        end
        
        local function removeVisuals(target)
            if self.data.visuals[target] then
                for _, obj in ipairs(self.data.visuals[target]) do
                    if obj and obj.Parent then pcall(function() obj:Destroy() end) end
                end
                self.data.visuals[target] = nil
            end
        end
        
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player then addVisuals(plr) end
        end
        
        table.insert(self.data.connections, Players.PlayerAdded:Connect(addVisuals))
        table.insert(self.data.connections, Players.PlayerRemoving:Connect(removeVisuals))
    end,
    
    cleanup = function(self)
        if self.data.visuals then
            for target, objs in pairs(self.data.visuals) do
                for _, obj in ipairs(objs) do
                    if obj and obj.Parent then pcall(function() obj:Destroy() end) end
                end
            end
            self.data.visuals = {}
        end
        if self.data.connections then
            for _, conn in ipairs(self.data.connections) do
                if conn and conn.Disconnect then
                    pcall(function() conn:Disconnect() end)
                end
            end
            self.data.connections = {}
        end
    end
}

ScriptModules["TimerESP"] = {
    name = "Timer ESP",
    category = "ESP",
    active = true,
    data = {},
    
    init = function(self)
        self.data.overlayFolder = Instance.new("Folder")
        self.data.overlayFolder.Name = "TimerOverlays"
        self.data.overlayFolder.Parent = player:WaitForChild("PlayerGui")
        self.data.connections = {}
        
        local function makeBillboard(target, sourceLabel)
            if not self.active then return end
            
            local billboard = Instance.new("BillboardGui")
            billboard.Size = UDim2.new(0, 200, 0, 60)
            billboard.StudsOffset = Vector3.new(0, 5, 0)
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 1e6
            billboard.Name = "TimerESP"
            billboard.Parent = self.data.overlayFolder
            billboard.Adornee = target
            
            local textLabel = Instance.new("TextLabel")
            textLabel.Size = UDim2.new(1, 0, 1, 0)
            textLabel.BackgroundTransparency = 1
            textLabel.Font = Enum.Font.SourceSansBold
            textLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
            textLabel.TextStrokeTransparency = 0
            textLabel.TextScaled = true
            textLabel.Parent = billboard
            
            local conn = RunService.RenderStepped:Connect(function()
                if not self.active then
                    billboard.Enabled = false
                    if conn and conn.Disconnect then
                        pcall(function() conn:Disconnect() end)
                    end
                    return
                end
                
                if sourceLabel.Parent and target then
                    local text = sourceLabel.Text
                    if text == "0s" or text == "0" then
                        textLabel.Text = "Unlocked"
                        textLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
                    else
                        textLabel.Text = text
                        textLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
                    end
                else
                    billboard.Enabled = false
                    if conn and conn.Disconnect then
                        pcall(function() conn:Disconnect() end)
                    end
                end
            end)
            
            table.insert(self.data.connections, conn)
        end
        
        local function isExcluded(text)
            text = string.lower(text or "")
            -- Exclude if contains "free", "sentry", "!", or "J3sus777"
            if text:find("free") or text:find("sentry") or text:find("!") or text:find("J3sus777") then
                return true
            end
            -- Exclude if contains any letters other than 's' (case insensitive)
            for char in text:gmatch("%a") do
                if char:lower() ~= "s" then
                    return true
                end
            end
            return false
        end
        
        local function scanTimers()
            if not self.active then return end
            
            for _, descendant in ipairs(workspace:GetDescendants()) do
                if descendant:IsA("TextLabel") and descendant.Text:match("%ds") and not isExcluded(descendant.Text) then
                    local adornee = descendant:FindFirstAncestorWhichIsA("BasePart")
                    if adornee and adornee.Position.Y <= 7 then
                        makeBillboard(adornee, descendant)
                    end
                end
            end
        end
        
        scanTimers()
        
        table.insert(self.data.connections, workspace.DescendantAdded:Connect(function(obj)
            if not self.active then return end
            if obj:IsA("TextLabel") and obj.Text:match("%ds") and not isExcluded(obj.Text) then
                local adornee = obj:FindFirstAncestorWhichIsA("BasePart")
                if adornee and adornee.Position.Y <= 7 then
                    makeBillboard(adornee, obj)
                end
            end
        end))
    end,
    
    cleanup = function(self)
        if self.data.overlayFolder then
            pcall(function() self.data.overlayFolder:Destroy() end)
            self.data.overlayFolder = nil
        end
        if self.data.connections then
            for _, conn in ipairs(self.data.connections) do
                if conn and conn.Disconnect then
                    pcall(function() conn:Disconnect() end)
                end
            end
            self.data.connections = {}
        end
    end
}

ScriptModules["InfiniteJump"] = {
    name = "Infinite Jump",
    category = "Movement",
    active = true,
    data = {},
    
    init = function(self)
        self.data.connections = {}
        
        local function updateCharacter()
            if not self.active then return end
            
            local char = player.Character or player.CharacterAdded:Wait()
            local humanoid = char:WaitForChild("Humanoid")
            local rootPart = char:WaitForChild("HumanoidRootPart")
            
            local conn = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
                if not self.active then return end
                if humanoid.Jump and rootPart then
                    rootPart.Velocity = Vector3.new(rootPart.Velocity.X, 50, rootPart.Velocity.Z)
                end
            end)
            
            table.insert(self.data.connections, conn)
        end
        
        table.insert(self.data.connections, player.CharacterAdded:Connect(updateCharacter))
        if player.Character then updateCharacter() end
    end,
    
    cleanup = function(self)
        if self.data.connections then
            for _, conn in ipairs(self.data.connections) do
                if conn and conn.Disconnect then
                    pcall(function() conn:Disconnect() end)
                end
            end
            self.data.connections = {}
        end
    end
}

ScriptModules["GrappleSpeed"] = {
    name = "Grapple Hook Speed",
    category = "Movement",
    active = true,
    data = {},
    
    init = function(self)
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        
        self.data.character = player.Character or player.CharacterAdded:Wait()
        self.data.humanoid = self.data.character:WaitForChild("Humanoid")
        
        -- Configuration
        local FIRE_INTERVAL = 0.1
        local SPEED_MULTIPLIER = 5
        local GRAPPLE_TOOL_NAME = "Grapple Hook"
        local Event = ReplicatedStorage.Packages.Net:WaitForChild("RE/UseItem")
        
        self.data.isHoldingGrapple = false
        self.data.connections = {}
        
        -- Check if player holds Grapple Hook
        local function checkForGrappleHook()
            if self.data.character then
                local tool = self.data.character:FindFirstChild(GRAPPLE_TOOL_NAME)
                return tool and tool:IsA("Tool")
            end
            return false
        end
        
        -- Apply speed boost
        local function applyDirectVelocity()
            if not self.active then return end
            if self.data.character and self.data.character:FindFirstChild("HumanoidRootPart") and self.data.isHoldingGrapple then
                local rootPart = self.data.character.HumanoidRootPart
                local moveVector = self.data.humanoid.MoveDirection
                if moveVector.Magnitude > 0 then
                    local currentVelocity = rootPart.AssemblyLinearVelocity
                    rootPart.AssemblyLinearVelocity = Vector3.new(
                        moveVector.X * self.data.humanoid.WalkSpeed * SPEED_MULTIPLIER,
                        currentVelocity.Y,
                        moveVector.Z * self.data.humanoid.WalkSpeed * SPEED_MULTIPLIER
                    )
                end
            end
        end
        
        -- Fire Grapple Hook
        local function fireGrappleHook()
            if not self.active then return end
            if self.data.isHoldingGrapple then
                pcall(function()
                    Event:FireServer(0.70743885040283)
                end)
            end
        end
        
        -- Auto-fire loop
        self.data.fireLoop = task.spawn(function()
            while self.active and self.data.character and self.data.character.Parent do
                fireGrappleHook()
                task.wait(FIRE_INTERVAL)
            end
        end)
        
        -- Movement loop
        local movementConn = RunService.Heartbeat:Connect(function()
            if not self.active then return end
            self.data.isHoldingGrapple = checkForGrappleHook()
            applyDirectVelocity()
        end)
        table.insert(self.data.connections, movementConn)
        
        -- Handle respawn
        local respawnConn = player.CharacterAdded:Connect(function(newChar)
            if not self.active then return end
            self.data.character = newChar
            self.data.humanoid = self.data.character:WaitForChild("Humanoid")
            self.data.isHoldingGrapple = false
        end)
        table.insert(self.data.connections, respawnConn)
        
        print("[Grapple Speed] Activated")
    end,
    
    cleanup = function(self)
        if self.data.fireLoop then
            task.cancel(self.data.fireLoop)
            self.data.fireLoop = nil
        end
        
        if self.data.connections then
            for _, conn in ipairs(self.data.connections) do
                if conn and conn.Disconnect then
                    pcall(function() conn:Disconnect() end)
                end
            end
            self.data.connections = {}
        end
        
        self.data.isHoldingGrapple = false
        print("[Grapple Speed] Deactivated")
    end
}

ScriptModules["AntiHit"] = {
    name = "Anti-Hit (Desync)",
    category = "Combat",
    active = true,
    data = {},
    
    init = function(self)
        local player = game.Players.LocalPlayer
        local RunService = game:GetService("RunService")
        local UserInputService = game:GetService("UserInputService")
        local PhysicsService = game:GetService("PhysicsService")

        self.data.character = player.Character or player.CharacterAdded:Wait()
        self.data.humanoidRootPart = self.data.character:WaitForChild("HumanoidRootPart")
        self.data.humanoid = self.data.character:WaitForChild("Humanoid")
        self.data.connections = {}

        self.data.DESYNC_ENABLED = false
        self.data.FAKE_POSITION = nil
        self.data.CLIENT_POSITION = nil
        self.data.UPDATE_INTERVAL = 0.5
        self.data.lastUpdate = tick()
        self.data.OFFSET_RANGE = 4
        self.data.DEBOUNCE = false
        self.data.serverPosBox = nil

        -- Godmode
        self.data.humanoid.MaxHealth = math.huge
        self.data.humanoid.Health = math.huge
        table.insert(self.data.connections, self.data.humanoid:GetPropertyChangedSignal("Health"):Connect(function()
            if self.active then
                self.data.humanoid.Health = math.huge
            end
        end))

        -- Setup collision groups
        pcall(function()
            PhysicsService:RegisterCollisionGroup("NoCollide")
            PhysicsService:CollisionGroupSetCollidable("NoCollide", "Default", false)
        end)

        -- Internal helper: equip Quantum Cloner if not already
        local function equipQuantumCloner()
            for _, item in pairs(self.data.character:GetChildren()) do
                if item:IsA("Tool") and item.Name == "Quantum Cloner" then
                    return true
                end
            end
            local backpack = player:FindFirstChild("Backpack")
            if backpack then
                local tool = backpack:FindFirstChild("Quantum Cloner")
                if tool then
                    self.data.humanoid:EquipTool(tool)
                    task.wait(0.2)
                    return true
                end
            end
            warn("[Anti-Hit] Quantum Cloner not found!")
            return false
        end

        -- Apply FFlags
        local function applyFFlags(enable)
            pcall(function()
                if enable then
                    setfflag("WorldStepMax", "-1000000")
                    setfflag("DFIntS2PhysicsSenderRate", "1")
                    setfflag("DFIntAssemblyExtentsExpansionStudHundredth", "1000")
                    setfflag("DFIntNetworkLatencyTolerance", "9999")
                    setfflag("DFIntTaskSchedulerTargetFps", "1")
                else
                    setfflag("WorldStepMax", "0")
                    setfflag("DFIntS2PhysicsSenderRate", "60")
                    setfflag("DFIntAssemblyExtentsExpansionStudHundredth", "0")
                    setfflag("DFIntNetworkLatencyTolerance", "100")
                    setfflag("DFIntTaskSchedulerTargetFps", "60")
                end
            end)
        end

        -- Ownership handling
        local function setClientOwnership()
            for _, part in pairs(self.data.character:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function()
                        part:SetNetworkOwner(player)
                        part.Anchored = false
                        if self.data.DESYNC_ENABLED then
                            part.CollisionGroup = "NoCollide"
                            part.CanCollide = false
                        else
                            part.CollisionGroup = "Default"
                            part.CanCollide = true
                        end
                    end)
                end
            end
            pcall(function()
                sethiddenproperty(player, "SimulationRadius", 99999)
            end)
        end

        -- Initialize desync
        local function initializeDesync()
            if self.data.humanoidRootPart then
                self.data.FAKE_POSITION = self.data.humanoidRootPart.CFrame
                self.data.CLIENT_POSITION = self.data.humanoidRootPart.CFrame
                setClientOwnership()
                applyFFlags(true)
            end
        end

        -- Toggle desync
        local function toggleDesync()
            self.data.DESYNC_ENABLED = not self.data.DESYNC_ENABLED
            if self.data.DESYNC_ENABLED then
                initializeDesync()
            else
                applyFFlags(false)
                setClientOwnership()
                self.data.CLIENT_POSITION = nil
                pcall(function()
                    self.data.humanoid:ChangeState(Enum.HumanoidStateType.Running)
                    self.data.humanoid.PlatformStand = false
                    self.data.humanoid.Sit = false
                    self.data.humanoid.AutoRotate = true
                end)
            end
        end

        -- Fire Quantum Cloner teleport
        local function fireQuantumTeleport()
            local Event = game:GetService("ReplicatedStorage").Packages.Net["RE/QuantumCloner/OnTeleport"]
            Event:FireServer()
            print("[Anti-Hit] Fired QuantumCloner teleport event.")
        end

        -- Main execution sequence (when pressing F)
        local function executeDesyncSequence()
            if self.data.DEBOUNCE then return end
            self.data.DEBOUNCE = true

            if not equipQuantumCloner() then
                self.data.DEBOUNCE = false
                return
            end

            -- Fire use item
            local UseItemEvent = game:GetService("ReplicatedStorage").Packages.Net["RE/UseItem"]
            UseItemEvent:FireServer()
            task.wait(0.3)

            fireQuantumTeleport()
            task.wait(0.4)
            toggleDesync()
            task.wait(0.8)
            toggleDesync()

            self.data.DEBOUNCE = false
        end

        -- F keybind
        table.insert(self.data.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed or not self.active then return end
            if input.KeyCode == Enum.KeyCode.F then
                executeDesyncSequence()
            end
        end))

        -- Heartbeat loop
        table.insert(self.data.connections, RunService.Heartbeat:Connect(function()
            if not self.active or not self.data.DESYNC_ENABLED or not self.data.humanoidRootPart then return end
            if tick() - self.data.lastUpdate >= self.data.UPDATE_INTERVAL then
                local moveOffset = self.data.humanoid.MoveDirection * 0.2
                local randomOffset = Vector3.new(
                    math.random(-self.data.OFFSET_RANGE/2, self.data.OFFSET_RANGE/2),
                    0,
                    math.random(-self.data.OFFSET_RANGE/2, self.data.OFFSET_RANGE/2)
                )
                self.data.FAKE_POSITION = self.data.humanoidRootPart.CFrame * CFrame.new(moveOffset + randomOffset)
                self.data.lastUpdate = tick()
            end
        end))
    end
}


--// ===========================
--// ADMIN PANEL (MISC MODULE)
--// ===========================
ScriptModules["AdminPanel"] = {
    name = "Admin Panel",
    category = "Misc",
    active = true,

    init = function(self)
        if self.active then return end
        self.active = true

        -- Create the ScreenGui
        local player = game:GetService("Players").LocalPlayer
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "VsterAdminPanel"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.Parent = player:WaitForChild("PlayerGui")

        -- Create the main frame
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 400, 0, 260)
        frame.Position = UDim2.new(0.5, -200, 0.5, -130)
        frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true
        frame.Parent = screenGui

        -- UI corner + shadow
        local uicorner = Instance.new("UICorner")
        uicorner.CornerRadius = UDim.new(0, 10)
        uicorner.Parent = frame

        -- Title bar
        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 30)
        title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        title.Text = "Vster Admin Panel"
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 16
        title.Parent = frame

        local titleCorner = Instance.new("UICorner")
        titleCorner.CornerRadius = UDim.new(0, 10)
        titleCorner.Parent = title

        -- Scrolling area for players
        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, -20, 1, -90)
        scroll.Position = UDim2.new(0, 10, 0, 40)
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.BackgroundTransparency = 1
        scroll.ScrollBarThickness = 6
        scroll.Parent = frame

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 5)
        layout.Parent = scroll

        -- Function: Refresh player list
        local function refreshPlayers()
            scroll:ClearAllChildren()
            layout.Parent = scroll
            for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, 0, 0, 28)
                btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
                btn.Text = plr.Name
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                btn.Font = Enum.Font.Gotham
                btn.TextSize = 14
                btn.Parent = scroll

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 6)
                corner.Parent = btn

                btn.MouseButton1Click:Connect(function()
                    setclipboard(plr.UserId)
                    game.StarterGui:SetCore("SendNotification", {
                        Title = "Copied!",
                        Text = "Copied " .. plr.Name .. "'s UserId",
                        Duration = 2
                    })
                end)
            end
            scroll.CanvasSize = UDim2.new(0, 0, 0, #game:GetService("Players"):GetPlayers() * 33)
        end

        refreshPlayers()
        game:GetService("Players").PlayerAdded:Connect(refreshPlayers)
        game:GetService("Players").PlayerRemoving:Connect(refreshPlayers)

        -- Remote Executor Button
        local execBtn = Instance.new("TextButton")
        execBtn.Size = UDim2.new(1, -20, 0, 30)
        execBtn.Position = UDim2.new(0, 10, 1, -40)
        execBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
        execBtn.Text = "Run Remote Executor"
        execBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        execBtn.Font = Enum.Font.GothamBold
        execBtn.TextSize = 15
        execBtn.Parent = frame

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = execBtn

        execBtn.MouseButton1Click:Connect(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/temujones1239012i3/11234123123/refs/heads/main/remote.lua"))()
        end)

        self.cleanup = function()
            if screenGui then screenGui:Destroy() end
            self.active = false
        end

        print("[Vster Hub] ✓ Admin Panel loaded under Misc")
    end,

    cleanup = function(self)
        if self.active then
            self.active = false
        end
    end
}


-- =======================
-- GUI CREATION
-- =======================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScriptHub"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Open Button (Small Circle)
local openButton = Instance.new("TextButton")
openButton.Name = "OpenButton"
openButton.Size = UDim2.new(0, 50, 0, 50)
openButton.Position = UDim2.new(0, 10, 0.4, -25)
openButton.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
openButton.Text = "☰"
openButton.Font = Enum.Font.SourceSansBold
openButton.TextSize = 24
openButton.TextColor3 = Color3.fromRGB(255, 255, 255)
openButton.BorderSizePixel = 0
openButton.Visible = true
openButton.Parent = screenGui

local openButtonCorner = Instance.new("UICorner")
openButtonCorner.CornerRadius = UDim.new(1, 0)
openButtonCorner.Parent = openButton

-- Main Frame
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 500, 0, 400)
mainFrame.Position = UDim2.new(0.5, -250, 0.5, -200)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = false
mainFrame.Parent = screenGui

openButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = true
    openButton.Visible = false
end)

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainFrame

-- Title Bar
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -80, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Vster Hub"
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextSize = 20
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

-- Close Button
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -35, 0, 5)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeButton.Text = "X"
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 18
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 5)
closeCorner.Parent = closeButton

closeButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
    openButton.Visible = true
end)

-- Minimize Button
local minimizeButton = Instance.new("TextButton")
minimizeButton.Size = UDim2.new(0, 30, 0, 30)
minimizeButton.Position = UDim2.new(1, -70, 0, 5)
minimizeButton.BackgroundColor3 = Color3.fromRGB(100, 100, 120)
minimizeButton.Text = "-"
minimizeButton.Font = Enum.Font.SourceSansBold
minimizeButton.TextSize = 18
minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeButton.Parent = titleBar

local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 5)
minimizeCorner.Parent = minimizeButton

local isMinimized = false
minimizeButton.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        mainFrame:TweenSize(UDim2.new(0, 500, 0, 40), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
    else
        mainFrame:TweenSize(UDim2.new(0, 500, 0, 400), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
    end
end)

-- Content Area
local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.Size = UDim2.new(1, -20, 1, -60)
contentFrame.Position = UDim2.new(0, 10, 0, 50)
contentFrame.BackgroundTransparency = 1
contentFrame.ClipsDescendants = true
contentFrame.Parent = mainFrame

-- Category Tabs
local tabFrame = Instance.new("Frame")
tabFrame.Size = UDim2.new(0, 120, 1, 0)
tabFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
tabFrame.BorderSizePixel = 0
tabFrame.Parent = contentFrame

local tabCorner = Instance.new("UICorner")
tabCorner.CornerRadius = UDim.new(0, 8)
tabCorner.Parent = tabFrame

local tabList = Instance.new("UIListLayout")
tabList.Padding = UDim.new(0, 5)
tabList.Parent = tabFrame

-- Scripts Container
local scriptsFrame = Instance.new("ScrollingFrame")
scriptsFrame.Size = UDim2.new(1, -130, 1, 0)
scriptsFrame.Position = UDim2.new(0, 130, 0, 0)
scriptsFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
scriptsFrame.BorderSizePixel = 0
scriptsFrame.ScrollBarThickness = 6
scriptsFrame.Parent = contentFrame

local scriptsCorner = Instance.new("UICorner")
scriptsCorner.CornerRadius = UDim.new(0, 8)
scriptsCorner.Parent = scriptsFrame

local scriptsList = Instance.new("UIListLayout")
scriptsList.Padding = UDim.new(0, 8)
scriptsList.Parent = scriptsFrame

local scriptsPadding = Instance.new("UIPadding")
scriptsPadding.PaddingTop = UDim.new(0, 10)
scriptsPadding.PaddingLeft = UDim.new(0, 10)
scriptsPadding.PaddingRight = UDim.new(0, 10)
scriptsPadding.Parent = scriptsFrame

-- Store all toggle buttons for syncing
local toggleButtons = {}

-- Function to update all toggle buttons for a script
local function updateAllToggles(scriptKey)
    if toggleButtons[scriptKey] then
        local scriptData = ScriptModules[scriptKey]
        for _, btn in ipairs(toggleButtons[scriptKey]) do
            if scriptData.active then
                btn.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
                btn.Text = "ON"
            else
                btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
                btn.Text = "OFF"
            end
        end
    end
end

-- Function to create script toggle button
local function createScriptButton(scriptKey, scriptData)
    local button = Instance.new("Frame")
    button.Size = UDim2.new(1, -10, 0, 50)
    button.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    button.Parent = scriptsFrame
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 6)
    buttonCorner.Parent = button
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -70, 1, 0)
    nameLabel.Position = UDim2.new(0, 10, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = scriptData.name
    nameLabel.Font = Enum.Font.SourceSans
    nameLabel.TextSize = 16
    nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = button
    
    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, 50, 0, 30)
    toggleButton.Position = UDim2.new(1, -60, 0.5, -15)
    toggleButton.BackgroundColor3 = scriptData.active and Color3.fromRGB(50, 200, 50) or Color3.fromRGB(200, 50, 50)
    toggleButton.Text = scriptData.active and "ON" or "OFF"
    toggleButton.Font = Enum.Font.SourceSansBold
    toggleButton.TextSize = 14
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.Parent = button
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 5)
    toggleCorner.Parent = toggleButton
    
    -- Store this button in the toggleButtons table
    if not toggleButtons[scriptKey] then
        toggleButtons[scriptKey] = {}
    end
    table.insert(toggleButtons[scriptKey], toggleButton)
    
    toggleButton.MouseButton1Click:Connect(function()
        scriptData.active = not scriptData.active
        
        if scriptData.active then
            scriptData:init()
        else
            scriptData:cleanup()
        end
        
        -- Update all toggle buttons for this script across all tabs
        updateAllToggles(scriptKey)
        
        -- Save settings
        saveSettings()
    end)
end

-- Function to update displayed scripts based on category
local function updateScriptsDisplay(category)
    -- Clear toggle button references for scripts not in view
    for key in pairs(toggleButtons) do
        toggleButtons[key] = {}
    end
    
    for _, child in ipairs(scriptsFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    for key, data in pairs(ScriptModules) do
        if category == "All" or data.category == category then
            createScriptButton(key, data)
        end
    end
    
    scriptsFrame.CanvasSize = UDim2.new(0, 0, 0, scriptsList.AbsoluteContentSize.Y + 20)
end

-- Create category tabs
local categories = {"All", "ESP", "Movement", "Combat", "Misc"}
local selectedCategory = "All"

for _, category in ipairs(categories) do
    local tabButton = Instance.new("TextButton")
    tabButton.Size = UDim2.new(1, -10, 0, 35)
    tabButton.BackgroundColor3 = (category == selectedCategory) and Color3.fromRGB(60, 60, 80) or Color3.fromRGB(40, 40, 55)
    tabButton.Text = category
    tabButton.Font = Enum.Font.SourceSansBold
    tabButton.TextSize = 15
    tabButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    tabButton.Parent = tabFrame
    
    local tabButtonCorner = Instance.new("UICorner")
    tabButtonCorner.CornerRadius = UDim.new(0, 5)
    tabButtonCorner.Parent = tabButton
    
    tabButton.MouseButton1Click:Connect(function()
        selectedCategory = category
        
        for _, child in ipairs(tabFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
            end
        end
        
        tabButton.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        updateScriptsDisplay(category)
    end)
end

-- Initial display
updateScriptsDisplay("All")

-- Make frame draggable
local dragging
local dragInput
local dragStart
local startPos

local function update(input)
    local delta = input.Position - dragStart
    mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

titleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        update(input)
    end
end)


ScriptModules["AutoFire"] = {
    name = "Auto-Fire Weapons",
    category = "Combat",
    active = true,
    data = {},
    
    init = function(self)
        local Event = game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Net"):WaitForChild("RE/UseItem")
        self.data.currentTool = nil
        self.data.fireConnection = nil
        
        local function fireToolAtPlayer(tool, target)
            if not tool or not target or not target.Character then return end
            local hrp = target.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            
            if tool.Name == "Laser Cape" or tool.Name == "Web Slinger" then
                Event:FireServer(hrp.Position, hrp)
            elseif tool.Name == "Taser Gun" then
                Event:FireServer(hrp)
            elseif tool.Name == "Bee Launcher" then
                Event:FireServer(target)
            end
        end
        
        local function getClosestPlayer()
            local char = player.Character
            if not char then return nil end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return nil end
            
            local closest, closestDist = nil, math.huge
            for _, other in ipairs(Players:GetPlayers()) do
                if other ~= player and other.Character then
                    local ohrp = other.Character:FindFirstChild("HumanoidRootPart")
                    if ohrp then
                        local dist = (hrp.Position - ohrp.Position).Magnitude
                        if dist < closestDist then
                            closestDist, closest = dist, other
                        end
                    end
                end
            end
            return closest
        end
        
        local function stopAutoFire()
            if self.data.fireConnection then
                self.data.fireConnection:Disconnect()
                self.data.fireConnection = nil
            end
        end
        
        local function startAutoFire(tool)
            stopAutoFire()
            self.data.fireConnection = RunService.Heartbeat:Connect(function()
                if not self.active then
                    stopAutoFire()
                    return
                end
                if not tool or tool.Parent ~= player.Character then
                    stopAutoFire()
                    return
                end
                local target = getClosestPlayer()
                if target then
                    fireToolAtPlayer(tool, target)
                end
            end)
        end
        
        self.data.toolCheckConnection = RunService.Heartbeat:Connect(function()
            if not self.active then return end
            local char = player.Character
            if not char then return end
            
            local equippedTool = nil
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") then
                    equippedTool = item
                    break
                end
            end
            
            if equippedTool ~= self.data.currentTool then
                self.data.currentTool = equippedTool
                if self.data.currentTool then
                    startAutoFire(self.data.currentTool)
                else
                    stopAutoFire()
                end
            end
        end)
        
        print("[Auto-Fire] Activated - Equip a weapon to auto-fire!")
    end,
    
    cleanup = function(self)
        if self.data.fireConnection then
            self.data.fireConnection:Disconnect()
            self.data.fireConnection = nil
        end
        if self.data.toolCheckConnection then
            self.data.toolCheckConnection:Disconnect()
            self.data.toolCheckConnection = nil
        end
        self.data.currentTool = nil
        print("[Auto-Fire] Deactivated")
    end
}

-- Update canvas size when scripts change
scriptsList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scriptsFrame.CanvasSize = UDim2.new(0, 0, 0, scriptsList.AbsoluteContentSize.Y + 20)
end)

-- FORCE START ALL MODULES
for key, module in pairs(ScriptModules) do
    module.active = true
    module:init()
    print("[Vster Hub] Started: " .. module.name)
end

-- Update UI buttons
task.wait(0.1)
for key in pairs(ScriptModules) do
    updateAllToggles(key)
end

print("[Vster Hub] ALL MODULES ARE NOW RUNNING")