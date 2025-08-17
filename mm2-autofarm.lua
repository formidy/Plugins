return {
    name = "mm2_coin_farmer",
    aliases = {"mm2farm", "mm2coinfarmer", "mm2cf"},
    version = "1.2.4",
    author = "morefein",
    description = "Automatically farms coins in MM2",
    category = "Farming",
    
    permissions = {
        "teleportation",
        "workspace_access",
        "event_system",
        "storage_access"
    },
    
    changelog = {
        ["1.2.4"] = "Fixed death/respawn handling and improved character checks",
        ["1.2.3"] = "Simplified camera handling to only set subject",
        ["1.2.2"] = "Fixed detection issues and improved pathfinding",
        ["1.2.1"] = "Added natural closest-coin pathfinding",
        ["1.2.0"] = "Faster farming, added coin highlights and camera focus",
        ["1.1.1"] = "Fixed getting stuck issues with timeout system",
        ["1.1.0"] = "Added smooth movement and better evasion",
        ["1.0.0"] = "Initial commit"
    },
    
    state = {
        isRunning = false,
        coinList = {},
        currentCoinIndex = 1,
        teleportCount = 0,
        descendantConnection = nil,
        removingConnection = nil,
        supportConnection = nil,
        floatConnection = nil,
        characterConnection = nil,
        supportPart = nil,
        lastNewCoinTime = 0,
        currentTween = nil,
        isTweening = false,
        lastActionTime = 0,
        tweenStartTime = 0,
        timeoutDuration = 3,
        highlights = {},
        lastPosition = nil,
        isPaused = false
    },
    
    onLoad = function(api)
        api.utils.log("mm2_coin_farmer", "MM2 Coin Farmer loaded!")
    end,
    
    onUnload = function(api)
        local state = api.plugin.state
        if state.currentTween then
            state.currentTween:Cancel()
            state.currentTween = nil
        end
        if state.descendantConnection then
            state.descendantConnection:Disconnect()
        end
        if state.removingConnection then
            state.removingConnection:Disconnect()
        end
        if state.supportConnection then
            state.supportConnection:Disconnect()
        end
        if state.floatConnection then
            state.floatConnection:Disconnect()
        end
        if state.characterConnection then
            state.characterConnection:Disconnect()
        end
        if state.supportPart then
            state.supportPart:Destroy()
        end
        for _, highlight in pairs(state.highlights) do
            if highlight and highlight.Parent then 
                highlight:Destroy() 
            end
        end
        local player = api.player.getLocalPlayer()
        if player.Character and player.Character:FindFirstChild("Humanoid") then
            workspace.CurrentCamera.CameraSubject = player.Character.Humanoid
        end
        state.isRunning = false
        api.utils.log("mm2_coin_farmer", "Plugin unloaded!")
    end,
    
    func = function(args, api)
        local state = api.plugin.state
        local RunService = game:GetService("RunService")
        local TweenService = game:GetService("TweenService")
        
        if state.isRunning then
            state.isRunning = false
            if state.currentTween then
                state.currentTween:Cancel()
                state.currentTween = nil
            end
            if state.descendantConnection then
                state.descendantConnection:Disconnect()
                state.descendantConnection = nil
            end
            if state.removingConnection then
                state.removingConnection:Disconnect()
                state.removingConnection = nil
            end
            if state.supportConnection then
                state.supportConnection:Disconnect()
                state.supportConnection = nil
            end
            if state.floatConnection then
                state.floatConnection:Disconnect()
                state.floatConnection = nil
            end
            if state.characterConnection then
                state.characterConnection:Disconnect()
                state.characterConnection = nil
            end
            if state.supportPart then
                state.supportPart:Destroy()
                state.supportPart = nil
            end
            for _, highlight in pairs(state.highlights) do
                if highlight and highlight.Parent then 
                    highlight:Destroy() 
                end
            end
            state.highlights = {}
            local player = api.player.getLocalPlayer()
            if player.Character and player.Character:FindFirstChild("Humanoid") then
                workspace.CurrentCamera.CameraSubject = player.Character.Humanoid
            end
            
            api.ui.showNotification("MM2 Coin Farmer", "Farming stopped", 2, "info")
            return
        end
        
        local player = api.player.getLocalPlayer()
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            api.ui.showNotification("Error", "Character not found", 3, "error")
            return
        end
        
        -- Character validation function
        local function isCharacterValid()
            return player.Character and 
                   player.Character:FindFirstChild("HumanoidRootPart") and 
                   player.Character:FindFirstChild("Humanoid") and
                   player.Character.HumanoidRootPart.Parent
        end
        
        -- Handle character death/respawn
        local function onCharacterDied()
            api.utils.log("mm2_coin_farmer", "Character died, pausing farming...")
            state.isPaused = true
            
            -- Cancel any ongoing tweens
            if state.currentTween then
                state.currentTween:Cancel()
                state.currentTween = nil
            end
            state.isTweening = false
            
            -- Clean up support part
            if state.supportPart then
                state.supportPart:Destroy()
                state.supportPart = nil
            end
            
            api.ui.showNotification("MM2 Farmer", "Character died, waiting for respawn...", 2, "warning")
        end
        
        local function onCharacterRespawned()
            if not state.isRunning then return end
            
            api.utils.log("mm2_coin_farmer", "Character respawned, resuming farming...")
            state.isPaused = false
            
            -- Reset position tracking
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                state.lastPosition = player.Character.HumanoidRootPart.Position
            end
            
            -- Recreate support part
            local supportPart = Instance.new("Part")
            supportPart.Name = "CoinFarmerSupportPart"
            supportPart.Size = Vector3.new(6, 1, 6)
            supportPart.Anchored = true
            supportPart.CanCollide = true
            supportPart.Transparency = 0.8
            supportPart.Material = Enum.Material.ForceField
            supportPart.Position = player.Character.HumanoidRootPart.Position - Vector3.new(0, 4, 0)
            supportPart.Parent = workspace
            state.supportPart = supportPart
            
            api.ui.showNotification("MM2 Farmer", "Respawned, resuming farming...", 2, "success")
        end
        
        -- Monitor character changes
        local function setupCharacterMonitoring()
            if state.characterConnection then
                state.characterConnection:Disconnect()
            end
            
            state.characterConnection = player.CharacterAdded:Connect(function(character)
                task.wait(1) -- Wait for character to fully load
                if state.isRunning then
                    onCharacterRespawned()
                end
            end)
            
            -- Monitor current character for death
            if player.Character then
                local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid.Died:Connect(function()
                        onCharacterDied()
                    end)
                end
            end
        end
        
        local function createCoinHighlight(coin)
            if state.highlights[coin] or not coin or not coin.Parent then return end
            
            pcall(function()
                local highlight = Instance.new("Highlight")
                highlight.Adornee = coin
                highlight.FillColor = Color3.fromRGB(255, 0, 0)
                highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                highlight.FillTransparency = 0.5
                highlight.OutlineTransparency = 0
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.Parent = coin
                
                state.highlights[coin] = highlight
            end)
        end
        
        local function removeCoinHighlight(coin)
            if state.highlights[coin] then
                pcall(function()
                    state.highlights[coin]:Destroy()
                    state.highlights[coin] = nil
                end)
            end
        end
        
        local function setCameraSubject(target)
            if not isCharacterValid() then return end
            pcall(function()
                workspace.CurrentCamera.CameraSubject = target
            end)
        end
        
        local function instantTeleport(targetCFrame)
            if not isCharacterValid() then return false end
            
            player.Character.HumanoidRootPart.CFrame = targetCFrame
            state.lastPosition = targetCFrame.Position
            return true
        end
        
        local function checkTimeout()
            if state.isTweening and (tick() - state.tweenStartTime) > state.timeoutDuration then
                api.utils.log("mm2_coin_farmer", "Tween timeout detected, cancelling...")
                if state.currentTween then
                    state.currentTween:Cancel()
                    state.currentTween = nil
                end
                state.isTweening = false
                state.lastActionTime = tick()
                if isCharacterValid() then
                    setCameraSubject(player.Character.Humanoid)
                end
                api.ui.showNotification("MM2 Farmer", "Movement timeout, continuing...", 1, "warning")
                return true
            end
            return false
        end
        
        local function resetTweenState()
            if state.currentTween then
                state.currentTween:Cancel()
                state.currentTween = nil
            end
            state.isTweening = false
            state.tweenStartTime = 0
        end
        
        local function getRandomTweenTime()
            return math.random(150, 300) / 100
        end
        
        local function getRandomOffset()
            return Vector3.new(
                math.random(-100, 100) / 100,
                math.random(-50, 50) / 100,
                math.random(-100, 100) / 100
            )
        end
        
        local function getRandomRotation()
            return math.random(-180, 180)
        end
        
        local function tweenToCoin(targetCFrame, targetCoin, callback)
            if state.isTweening or not isCharacterValid() then
                api.utils.log("mm2_coin_farmer", "Cannot start tween - already tweening or no character")
                return false
            end
            
            resetTweenState()
            state.isTweening = true
            state.tweenStartTime = tick()
            
            local humanoidRootPart = player.Character.HumanoidRootPart
            
            if targetCoin and targetCoin.Parent then
                setCameraSubject(targetCoin)
            end
            
            local tweenTime = math.min(getRandomTweenTime(), state.timeoutDuration - 0.2)
            local easingStyles = {Enum.EasingStyle.Quad, Enum.EasingStyle.Quint, Enum.EasingStyle.Sine, Enum.EasingStyle.Quart}
            local randomStyle = easingStyles[math.random(1, #easingStyles)]
            
            local tweenInfo = TweenInfo.new(
                tweenTime,
                randomStyle,
                Enum.EasingDirection.Out,
                0,
                false,
                0
            )
            
            local offsetTarget = targetCFrame + getRandomOffset()
            local rotatedTarget = offsetTarget * CFrame.Angles(0, math.rad(getRandomRotation()), 0)
            
            state.currentTween = TweenService:Create(humanoidRootPart, tweenInfo, {CFrame = rotatedTarget})
            
            state.currentTween.Completed:Connect(function(playbackState)
                api.utils.log("mm2_coin_farmer", "Tween completed with state: " .. tostring(playbackState))
                resetTweenState()
                state.lastActionTime = tick()
                
                if isCharacterValid() then
                    setCameraSubject(player.Character.Humanoid)
                end
                
                if playbackState == Enum.PlaybackState.Completed then
                    state.lastPosition = rotatedTarget.Position
                    
                    if callback then
                        task.spawn(callback)
                    end
                end
            end)
            
            state.currentTween:Play()
            api.utils.log("mm2_coin_farmer", "Started tween to coin")
            return true
        end
        
        local function isValidCoin(coinData)
            return coinData and coinData.obj and coinData.obj.Parent and coinData.obj:IsA("BasePart")
        end
        
        local function findAllCoins()
            local coins = {}
            local foundCoins = {}
            
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("BasePart") and (obj.Name == "coin_server" or obj.Name == "Coin_Server") and obj.Parent and not foundCoins[obj] then
                    foundCoins[obj] = true
                    createCoinHighlight(obj)
                    table.insert(coins, {
                        obj = obj, 
                        position = obj.CFrame, 
                        touched = false,
                        visited = false
                    })
                    api.utils.log("mm2_coin_farmer", "Found coin: " .. obj.Name)
                end
            end
            
            return coins
        end
        
        local function cleanupInvalidCoins()
            for i = #state.coinList, 1, -1 do
                local coinData = state.coinList[i]
                if not isValidCoin(coinData) then
                    removeCoinHighlight(coinData.obj)
                    table.remove(state.coinList, i)
                end
            end
        end
        
        local function setupTouchDetection(coinData)
            if coinData.obj and coinData.obj:IsA("BasePart") and isCharacterValid() then
                local connection
                connection = coinData.obj.Touched:Connect(function(hit)
                    if hit.Parent == player.Character then
                        coinData.touched = true
                        removeCoinHighlight(coinData.obj)
                        connection:Disconnect()
                    end
                end)
            end
        end
        
        local function resetAllTouchStates()
            for _, coinData in pairs(state.coinList) do
                if isValidCoin(coinData) then
                    coinData.touched = false
                    coinData.visited = false
                    createCoinHighlight(coinData.obj)
                    setupTouchDetection(coinData)
                end
            end
        end
        
        local function getRandomSpawn()
            local lobby = workspace:FindFirstChild("Lobby")
            if lobby then
                local spawns = lobby:FindFirstChild("Spawns")
                if spawns then
                    local spawnList = {}
                    for _, child in pairs(spawns:GetChildren()) do
                        if child:IsA("BasePart") and child.Position then
                            table.insert(spawnList, child)
                        end
                    end
                    if #spawnList > 0 then
                        return spawnList[math.random(1, #spawnList)]
                    end
                end
            end
            return nil
        end
        
        local function getClosestCoin()
            cleanupInvalidCoins()
            
            local currentPos = state.lastPosition
            if not currentPos and isCharacterValid() then
                currentPos = player.Character.HumanoidRootPart.Position
            end
            
            if not currentPos then return nil end
            
            local closestIndex = nil
            local closestDistance = math.huge
            
            for i, coinData in pairs(state.coinList) do
                if isValidCoin(coinData) and not coinData.touched then
                    local distance = (currentPos - coinData.obj.Position).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestIndex = i
                    end
                end
            end
            
            if closestIndex then
                api.utils.log("mm2_coin_farmer", "Found closest coin at distance " .. math.floor(closestDistance))
            end
            
            return closestIndex
        end
        
        state.isRunning = true
        state.coinList = findAllCoins()
        state.currentCoinIndex = 1
        state.teleportCount = 0
        state.lastNewCoinTime = tick()
        state.isTweening = false
        state.lastActionTime = tick()
        state.tweenStartTime = 0
        state.highlights = {}
        state.lastPosition = nil
        state.isPaused = false
        
        if isCharacterValid() then
            state.lastPosition = player.Character.HumanoidRootPart.Position
        end
        
        -- Setup character monitoring first
        setupCharacterMonitoring()
        
        local originalPosition = player.Character.HumanoidRootPart.CFrame
        
        local supportPart = Instance.new("Part")
        supportPart.Name = "CoinFarmerSupportPart"
        supportPart.Size = Vector3.new(6, 1, 6)
        supportPart.Anchored = true
        supportPart.CanCollide = true
        supportPart.Transparency = 0.8
        supportPart.Material = Enum.Material.ForceField
        supportPart.Position = player.Character.HumanoidRootPart.Position - Vector3.new(0, 4, 0)
        supportPart.Parent = workspace
        state.supportPart = supportPart
        
        state.supportConnection = RunService.Heartbeat:Connect(function()
            if isCharacterValid() and state.supportPart and not state.isPaused then
                local currentPos = player.Character.HumanoidRootPart.Position
                state.supportPart.Position = Vector3.new(currentPos.X, currentPos.Y - 4, currentPos.Z)
            end
        end)
        
        local lastSafeY = player.Character.HumanoidRootPart.Position.Y
        state.floatConnection = RunService.Heartbeat:Connect(function()
            if isCharacterValid() and not state.isTweening and not state.isPaused then
                local humanoidRootPart = player.Character.HumanoidRootPart
                local currentPos = humanoidRootPart.Position
                
                if currentPos.Y < lastSafeY - 2 then
                    humanoidRootPart.CFrame = CFrame.new(currentPos.X, lastSafeY, currentPos.Z) * (humanoidRootPart.CFrame - humanoidRootPart.Position)
                    humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
                else
                    lastSafeY = math.max(lastSafeY, currentPos.Y)
                end
            end
        end)
        
        for _, coinData in pairs(state.coinList) do
            setupTouchDetection(coinData)
        end
        
        local function teleportLoop()
            task.spawn(function()
                while state.isRunning do
                    -- Wait if paused (character died/respawning)
                    if state.isPaused then
                        task.wait(1)
                        continue
                    end
                    
                    -- Ensure character is still valid
                    if not isCharacterValid() then
                        task.wait(1)
                        continue
                    end
                    
                    checkTimeout()
                    
                    if state.isTweening then
                        task.wait(0.1)
                        continue
                    end
                    
                    cleanupInvalidCoins()
                    
                    if #state.coinList == 0 then
                        api.ui.showNotification("MM2 Farmer", "No valid coins found, waiting...", 1, "warning")
                        task.wait(2)
                    elseif state.teleportCount >= 2 then
                        local randomSpawn = getRandomSpawn()
                        if randomSpawn and randomSpawn.Position then
                            local humanoid = player.Character:FindFirstChildOfClass('Humanoid')
                            if humanoid and humanoid.SeatPart then
                                humanoid.Sit = false
                            end
                            
                            local spawnPos = randomSpawn.Position
                            local spawnHeight = math.random(3, 7)
                            local teleportCFrame = CFrame.new(spawnPos.X, spawnPos.Y + spawnHeight, spawnPos.Z)
                            
                            if instantTeleport(teleportCFrame) then
                                lastSafeY = spawnPos.Y + spawnHeight
                                api.ui.showNotification("MM2 Farmer", "Returned to lobby spawn", 1, "info")
                                state.teleportCount = 0
                                task.wait(0.1)
                            end
                        end
                    else
                        local targetIndex = getClosestCoin()
                        if targetIndex then
                            local target = state.coinList[targetIndex]
                            
                            if isValidCoin(target) then
                                local humanoid = player.Character:FindFirstChildOfClass('Humanoid')
                                if humanoid and humanoid.SeatPart then
                                    humanoid.Sit = false
                                end
                                
                                if isCharacterValid() then
                                    local coinPos = target.obj.Position
                                    local coinSize = target.obj.Size
                                    local heightOffset = math.random(200, 400) / 100
                                    local teleportCFrame = CFrame.new(coinPos.X, coinPos.Y + (coinSize.Y / 2) + heightOffset, coinPos.Z)
                                    
                                    local success = tweenToCoin(teleportCFrame, target.obj, function()
                                        target.visited = true
                                        lastSafeY = coinPos.Y + (coinSize.Y / 2) + heightOffset
                                        state.teleportCount = state.teleportCount + 1
                                        
                                        local remainingCoins = 0
                                        for _, coinData in pairs(state.coinList) do
                                            if isValidCoin(coinData) and not coinData.touched then
                                                remainingCoins = remainingCoins + 1
                                            end
                                        end
                                        
                                        api.ui.showNotification("MM2 Farmer", "Reached coin (Count: " .. state.teleportCount .. "/2, Remaining: " .. remainingCoins .. ")", 1, "success")
                                    end)
                                    
                                    if not success then
                                        api.utils.log("mm2_coin_farmer", "Failed to start tween to coin, skipping...")
                                        target.touched = true
                                        removeCoinHighlight(target.obj)
                                    end
                                end
                            else
                                api.utils.log("mm2_coin_farmer", "Skipping invalid coin")
                            end
                        else
                            api.ui.showNotification("MM2 Farmer", "No valid coins to teleport to", 1, "warning")
                            task.wait(1)
                        end
                    end
                    
                    task.wait(0.1)
                end
            end)
        end
        
        state.descendantConnection = workspace.DescendantAdded:Connect(function(obj)
            if obj:IsA("BasePart") and (obj.Name == "coin_server" or obj.Name == "Coin_Server") then
                task.wait(0.2)
                if obj.Parent then
                    createCoinHighlight(obj)
                    local newCoin = {
                        obj = obj,
                        position = obj.CFrame,
                        touched = false,
                        visited = false
                    }
                    table.insert(state.coinList, newCoin)
                    setupTouchDetection(newCoin)
                    state.lastNewCoinTime = tick()
                    
                    api.ui.showNotification("New Coin", "Found new coin! (" .. #state.coinList .. " total)", 2, "info")
                    api.utils.log("mm2_coin_farmer", "New coin detected, total coins: " .. #state.coinList)
                end
            end
        end)
        
        state.removingConnection = workspace.DescendantRemoving:Connect(function(obj)
            if obj:IsA("BasePart") and (obj.Name == "coin_server" or obj.Name == "Coin_Server") then
                removeCoinHighlight(obj)
                for i = #state.coinList, 1, -1 do
                    local coinData = state.coinList[i]
                    if coinData.obj == obj then
                        table.remove(state.coinList, i)
                        api.utils.log("mm2_coin_farmer", "Coin removed, remaining coins: " .. #state.coinList)
                        break
                    end
                end
            end
        end)
        
        teleportLoop()
        api.ui.showNotification("MM2 Coin Farmer", "Started farming! Found " .. #state.coinList .. " coins", 3, "success")
        api.storage.save("mm2_coin_farmer", "last_started", os.time())
    end
}
