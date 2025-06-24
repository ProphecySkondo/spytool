if not getrawmetatable or not getnamecallmethod then
    print("> Executor not supported!")
    return
end

local Players, TweenService, UserInputService = game:GetService("Players"), game:GetService("TweenService"), game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local enabled, showArgs, maxLogs, paused, autoSave, showTimestamps, filterEnabled, currentFilter, highlightNew, monitoring = true, true, 500, false, false, true, false, "", true, true
local log = loadstring(game:HttpGet("https://gist.githubusercontent.com/ProphecySkondo/55d0332827156d0798fd0b533aa1f188/raw/afd3800978e1799e2feacec9813ff809015825ff/gistfile1.txt"))()
local gui, mainFrame, logFrame, settingsFrame, miniExecutor, httpLogFrame, decompilerFrame, decompilerContainer, scriptViewer
local logs, filteredLogs, searchResults, httpLogs, decompilerLogs = {}, {}, {}, {}, {}
local scriptViewerVisible = false
local selectedRemote = nil
local miniExecutorVisible = false
local currentTab = "RemoteSpy"

local stats = {
    totalFires = 0,
    totalInvokes = 0,
    totalHttpRequests = 0,
    uniqueRemotes = {},
    sessionStart = tick(),
    popularRemotes = {},
    recentActivity = {}
}

local remoteHistory, blacklistedRemotes, favoriteRemotes, exportData, notificationQueue, blockedRemotes = {}, {}, {}, {}, {}, {}
local remoteGroups = {}
local expandedGroups = {}
local buttonInteraction = false

makeButtonNonDraggable = function(button)
    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            buttonInteraction = true
        end
    end)
    
    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            buttonInteraction = false
        end
    end)
end

formatValue = function(v)
    local t = type(v)
    if t == "string" then
        return '"' .. (v:len() > 20 and v:sub(1, 20) .. "..." or v) .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        return "table"
    elseif t == "userdata" then
        local success, name = pcall(function() return v.Name end)
        return success and (tostring(v) .. "(" .. name .. ")") or tostring(v)
    else
        return tostring(v)
    end
end

getPath = function(obj)
    local parts = {}
    while obj and obj ~= game do
        table.insert(parts, 1, obj.Name or "Unknown")
        obj = obj.Parent
    end
    return table.concat(parts, ".")
end

getCallingScript = function()
    local success, script = pcall(function()
        if getcallingscript then
            return getcallingscript()
        elseif getfenv then
            local env = getfenv(2)
            if env and env.script then
                return env.script
            end
        end
        return nil
    end)
    return success and script or nil
end

parseArguments = function(argsString)
    if not argsString or argsString == "(no arguments)" or argsString == "" then
        return {}
    end
    
    local args = {}
    local current = ""
    local inString = false
    local stringChar = nil
    local depth = 0
    local i = 1
    
    while i <= #argsString do
        local char = argsString:sub(i, i)
        
        if not inString then
            if char == '"' or char == "'" then
                inString = true
                stringChar = char
                current = current .. char
            elseif char == "{" or char == "(" then
                depth = depth + 1
                current = current .. char
            elseif char == "}" or char == ")" then
                depth = depth - 1
                current = current .. char
            elseif char == "," and depth == 0 then
                local trimmed = current:match("^%s*(.-)%s*$")
                if trimmed ~= "" then
                    local value = loadstring("return " .. trimmed)
                    if value then
                        local success, result = pcall(value)
                        if success then
                            table.insert(args, result)
                        else
                            table.insert(args, trimmed)
                        end
                    else
                        table.insert(args, trimmed)
                    end
                end
                current = ""
            else
                current = current .. char
            end
        else
            current = current .. char
            if char == stringChar and argsString:sub(i-1, i-1) ~= "\\" then
                inString = false
                stringChar = nil
            end
        end
        
        i = i + 1
    end
    
    if current ~= "" then
        local trimmed = current:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            local value = loadstring("return " .. trimmed)
            if value then
                local success, result = pcall(value)
                if success then
                    table.insert(args, result)
                else
                    table.insert(args, trimmed)
                end
            else
                table.insert(args, trimmed)
            end
        end
    end
    
    return args
end

createScriptViewer = function()
    if scriptViewer then
        scriptViewer:Destroy()
    end
    
    scriptViewer = Instance.new("Frame")
    scriptViewer.Name = "ScriptViewer"
    scriptViewer.Size = UDim2.new(0, 600, 0, 400)
    scriptViewer.Position = UDim2.new(0.5, -300, 0.5, -200)
    scriptViewer.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    scriptViewer.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    scriptViewer.BorderSizePixel = 2
    scriptViewer.Visible = false
    scriptViewer.ZIndex = 10
    scriptViewer.Parent = gui
    
    local viewerTitle = Instance.new("Frame")
    viewerTitle.Name = "ViewerTitle"
    viewerTitle.Size = UDim2.new(1, 0, 0, 25)
    viewerTitle.Position = UDim2.new(0, 0, 0, 0)
    viewerTitle.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    viewerTitle.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    viewerTitle.BorderSizePixel = 1
    viewerTitle.ZIndex = 11
    viewerTitle.Parent = scriptViewer
    
    local viewerTitleText = Instance.new("TextLabel")
    viewerTitleText.Name = "ViewerTitleText"
    viewerTitleText.Size = UDim2.new(1, -50, 1, 0)
    viewerTitleText.Position = UDim2.new(0, 5, 0, 0)
    viewerTitleText.BackgroundTransparency = 1
    viewerTitleText.Text = "Script Viewer"
    viewerTitleText.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    viewerTitleText.TextSize = 14
    viewerTitleText.Font = Enum.Font.SourceSans
    viewerTitleText.TextXAlignment = Enum.TextXAlignment.Left
    viewerTitleText.ZIndex = 12
    viewerTitleText.Parent = viewerTitle
    
    local viewerCloseBtn = Instance.new("TextButton")
    viewerCloseBtn.Name = "ViewerCloseBtn"
    viewerCloseBtn.Size = UDim2.new(0, 20, 0, 20)
    viewerCloseBtn.Position = UDim2.new(1, -25, 0, 2)
    viewerCloseBtn.BackgroundColor3 = Color3.new(0.8, 0.2, 0.2)
    viewerCloseBtn.BorderColor3 = Color3.new(0.9, 0.3, 0.3)
    viewerCloseBtn.BorderSizePixel = 1
    viewerCloseBtn.Text = "X"
    viewerCloseBtn.TextColor3 = Color3.new(1, 1, 1)
    viewerCloseBtn.TextSize = 12
    viewerCloseBtn.Font = Enum.Font.SourceSans
    viewerCloseBtn.ZIndex = 12
    viewerCloseBtn.Parent = viewerTitle
    
    local viewerControls = Instance.new("Frame")
    viewerControls.Name = "ViewerControls"
    viewerControls.Size = UDim2.new(1, -10, 0, 30)
    viewerControls.Position = UDim2.new(0, 5, 0, 30)
    viewerControls.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    viewerControls.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    viewerControls.BorderSizePixel = 1
    viewerControls.ZIndex = 11
    viewerControls.Parent = scriptViewer
    
    local copySourceBtn = Instance.new("TextButton")
    copySourceBtn.Name = "CopySourceBtn"
    copySourceBtn.Size = UDim2.new(0, 80, 1, -4)
    copySourceBtn.Position = UDim2.new(0, 5, 0, 2)
    copySourceBtn.BackgroundColor3 = Color3.new(0.2, 0.6, 0.2)
    copySourceBtn.BorderColor3 = Color3.new(0.3, 0.7, 0.3)
    copySourceBtn.BorderSizePixel = 1
    copySourceBtn.Text = "Copy Source"
    copySourceBtn.TextColor3 = Color3.new(1, 1, 1)
    copySourceBtn.TextSize = 11
    copySourceBtn.Font = Enum.Font.SourceSans
    copySourceBtn.ZIndex = 12
    copySourceBtn.Parent = viewerControls
    
    local saveScriptBtn = Instance.new("TextButton")
    saveScriptBtn.Name = "SaveScriptBtn"
    saveScriptBtn.Size = UDim2.new(0, 70, 1, -4)
    saveScriptBtn.Position = UDim2.new(0, 90, 0, 2)
    saveScriptBtn.BackgroundColor3 = Color3.new(0.6, 0.4, 0.2)
    saveScriptBtn.BorderColor3 = Color3.new(0.7, 0.5, 0.3)
    saveScriptBtn.BorderSizePixel = 1
    saveScriptBtn.Text = "Save Script"
    saveScriptBtn.TextColor3 = Color3.new(1, 1, 1)
    saveScriptBtn.TextSize = 11
    saveScriptBtn.Font = Enum.Font.SourceSans
    saveScriptBtn.ZIndex = 12
    saveScriptBtn.Parent = viewerControls
    
    local scriptInfoLabel = Instance.new("TextLabel")
    scriptInfoLabel.Name = "ScriptInfoLabel"
    scriptInfoLabel.Size = UDim2.new(1, -170, 1, 0)
    scriptInfoLabel.Position = UDim2.new(0, 165, 0, 0)
    scriptInfoLabel.BackgroundTransparency = 1
    scriptInfoLabel.Text = "No script loaded"
    scriptInfoLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    scriptInfoLabel.TextSize = 11
    scriptInfoLabel.Font = Enum.Font.SourceSans
    scriptInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    scriptInfoLabel.ZIndex = 12
    scriptInfoLabel.Parent = viewerControls
    
    local sourceFrame = Instance.new("ScrollingFrame")
    sourceFrame.Name = "SourceFrame"
    sourceFrame.Size = UDim2.new(1, -10, 1, -70)
    sourceFrame.Position = UDim2.new(0, 5, 0, 65)
    sourceFrame.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    sourceFrame.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    sourceFrame.BorderSizePixel = 1
    sourceFrame.ScrollBarThickness = 8
    sourceFrame.ScrollBarImageColor3 = Color3.new(0.3, 0.3, 0.3)
    sourceFrame.ScrollBarImageTransparency = 0
    sourceFrame.ZIndex = 11
    sourceFrame.Parent = scriptViewer
    
    local sourceText = Instance.new("TextLabel")
    sourceText.Name = "SourceText"
    sourceText.Size = UDim2.new(1, -10, 1, 0)
    sourceText.Position = UDim2.new(0, 5, 0, 0)
    sourceText.BackgroundTransparency = 1
    sourceText.Text = "No source code available"
    sourceText.TextColor3 = Color3.new(0.9, 0.9, 0.9)
    sourceText.TextSize = 12
    sourceText.Font = Enum.Font.Code
    sourceText.TextXAlignment = Enum.TextXAlignment.Left
    sourceText.TextYAlignment = Enum.TextYAlignment.Top
    sourceText.TextWrapped = true
    sourceText.ZIndex = 12
    sourceText.Parent = sourceFrame
    
    viewerCloseBtn.MouseButton1Click:Connect(function()
        scriptViewer.Visible = false
        scriptViewerVisible = false
    end)
    
    local dragging, dragStart, startPos = false, nil, nil
    viewerTitle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = scriptViewer.Position
        end
    end)
    
    viewerTitle.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            scriptViewer.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    viewerTitle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

showScriptInViewer = function(scriptName, scriptPath, source, scriptType)
    if not scriptViewer then
        createScriptViewer()
    end
    
    local viewerElements = {
        titleText = scriptViewer:FindFirstChild("ViewerTitle"):FindFirstChild("ViewerTitleText"),
        infoLabel = scriptViewer:FindFirstChild("ViewerControls"):FindFirstChild("ScriptInfoLabel"),
        sourceText = scriptViewer:FindFirstChild("SourceFrame"):FindFirstChild("SourceText"),
        sourceFrame = scriptViewer:FindFirstChild("SourceFrame"),
        copyBtn = scriptViewer:FindFirstChild("ViewerControls"):FindFirstChild("CopySourceBtn"),
        saveBtn = scriptViewer:FindFirstChild("ViewerControls"):FindFirstChild("SaveScriptBtn")
    }
    
    viewerElements.titleText.Text = "Script Viewer - " .. scriptName
    viewerElements.infoLabel.Text = scriptType .. " | " .. scriptPath
    viewerElements.sourceText.Text = source or "Failed to decompile script"
    
    local textBounds = game:GetService("TextService"):GetTextSize(
        viewerElements.sourceText.Text,
        viewerElements.sourceText.TextSize,
        viewerElements.sourceText.Font,
        Vector2.new(viewerElements.sourceFrame.AbsoluteSize.X - 10, math.huge)
    )
    
    viewerElements.sourceText.Size = UDim2.new(1, -10, 0, math.max(textBounds.Y, viewerElements.sourceFrame.AbsoluteSize.Y))
    viewerElements.sourceFrame.CanvasSize = UDim2.new(0, 0, 0, textBounds.Y + 10)
    
    viewerElements.copyBtn.MouseButton1Click:Connect(function()
        copyToClipboard(source or "Failed to decompile script")
        addLog("> Script source copied: " .. scriptName, Color3.new(0.5, 1, 0.5))
    end)
    
    viewerElements.saveBtn.MouseButton1Click:Connect(function()
        if writefile then
            local fileName = scriptName:gsub("[^%w%-%_]", "_") .. ".lua"
            writefile(fileName, source or "Failed to decompile script")
            addLog("> Script saved as: " .. fileName, Color3.new(0.5, 1, 0.5))
        else
            addLog("> writefile not supported by executor", Color3.new(1, 0.8, 0.2))
        end
    end)
    
    scriptViewer.Visible = true
    scriptViewerVisible = true
end

formatHttpLogEntry = function(method, url, headers, data, response)
    if not method or not url then
        return ""
    end
    local text = method .. "\n" .. url
    if headers and type(headers) == "table" then
        text = text .. "\n\nHeaders:"
        for key, value in pairs(headers) do
            text = text .. string.format("\n%s: %s", tostring(key), tostring(value))
        end
    end
    if data and data ~= "" then
        text = text .. "\n\nData: " .. tostring(data)
    end
    if response and response ~= "" then
        text = text .. "\n\nResponse: " .. tostring(response)
    end
    return text
end

addHttpLog = function(method, url, headers, data, response, statusCode)
    if not gui or not httpLogFrame then return end
    
    local yPos = 0
    for _, log in ipairs(httpLogs) do
        yPos = yPos + log.Size.Y.Offset
    end
    
    local logContainer = Instance.new("TextButton")
    logContainer.Size = UDim2.new(1, -10, 0, 80)
    logContainer.Position = UDim2.new(0, 5, 0, yPos)
    logContainer.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    logContainer.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    logContainer.BorderSizePixel = 1
    logContainer.AutoButtonColor = false
    logContainer.Text = ""
    logContainer.Parent = httpLogFrame
    
    local methodLabel = Instance.new("TextLabel")
    methodLabel.Size = UDim2.new(0, 60, 0, 20)
    methodLabel.Position = UDim2.new(0, 5, 0, 5)
    methodLabel.BackgroundTransparency = 1
    methodLabel.Text = method
    methodLabel.TextColor3 = method == "GET" and Color3.new(0.2, 0.8, 0.2) or Color3.new(0.8, 0.6, 0.2)
    methodLabel.TextSize = 12
    methodLabel.Font = Enum.Font.SourceSansBold
    methodLabel.TextXAlignment = Enum.TextXAlignment.Left
    methodLabel.Parent = logContainer
    
    local urlLabel = Instance.new("TextLabel")
    urlLabel.Size = UDim2.new(1, -70, 0, 20)
    urlLabel.Position = UDim2.new(0, 70, 0, 5)
    urlLabel.BackgroundTransparency = 1
    urlLabel.Text = url:len() > 50 and url:sub(1, 50) .. "..." or url
    urlLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    urlLabel.TextSize = 11
    urlLabel.Font = Enum.Font.SourceSans
    urlLabel.TextXAlignment = Enum.TextXAlignment.Left
    urlLabel.Parent = logContainer
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -10, 0, 15)
    statusLabel.Position = UDim2.new(0, 5, 0, 25)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Status: " .. tostring(statusCode or "Unknown") .. " | Data: " .. (data and data:len() > 30 and data:sub(1, 30) .. "..." or (data or "None"))
    statusLabel.TextColor3 = Color3.new(0.6, 0.6, 0.6)
    statusLabel.TextSize = 10
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = logContainer
    
    local responseLabel = Instance.new("TextLabel")
    responseLabel.Size = UDim2.new(1, -10, 0, 15)
    responseLabel.Position = UDim2.new(0, 5, 0, 40)
    responseLabel.BackgroundTransparency = 1
    responseLabel.Text = "Response: " .. (response and response:len() > 40 and response:sub(1, 40) .. "..." or (response or "None"))
    responseLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
    responseLabel.TextSize = 10
    responseLabel.Font = Enum.Font.SourceSans
    responseLabel.TextXAlignment = Enum.TextXAlignment.Left
    responseLabel.Parent = logContainer
    
    local headersLabel = Instance.new("TextLabel")
    headersLabel.Size = UDim2.new(1, -10, 0, 15)
    headersLabel.Position = UDim2.new(0, 5, 0, 55)
    headersLabel.BackgroundTransparency = 1
    local headerCount = 0
    if headers and type(headers) == "table" then
        for _ in pairs(headers) do
            headerCount = headerCount + 1
        end
    end
    headersLabel.Text = "Headers: " .. headerCount .. " items"
    headersLabel.TextColor3 = Color3.new(0.4, 0.4, 0.4)
    headersLabel.TextSize = 10
    headersLabel.Font = Enum.Font.SourceSans
    headersLabel.TextXAlignment = Enum.TextXAlignment.Left
    headersLabel.Parent = logContainer
    
    logContainer.MouseEnter:Connect(function()
        logContainer.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    end)
    
    logContainer.MouseLeave:Connect(function()
        logContainer.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    end)
    
    logContainer.MouseButton1Click:Connect(function()
        local fullData = formatHttpLogEntry(method, url, headers, data, response)
        copyToClipboard(fullData)
        addLog("> HTTP request data copied!", Color3.new(0.5, 1, 0.5))
    end)
    
    table.insert(httpLogs, logContainer)
    
    if #httpLogs > maxLogs then
        httpLogs[1]:Destroy()
        table.remove(httpLogs, 1)
        
        local yPos = 0
        for i, log in ipairs(httpLogs) do
            log.Position = UDim2.new(0, 5, 0, yPos)
            yPos = yPos + log.Size.Y.Offset
        end
    end
    
    local totalHeight = 0
    for _, log in ipairs(httpLogs) do
        totalHeight = totalHeight + log.Size.Y.Offset
    end
    
    httpLogFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
    httpLogFrame.CanvasPosition = Vector2.new(0, httpLogFrame.CanvasSize.Y.Offset)
end

addDecompilerLog = function(scriptName, scriptPath, source, scriptType)
    if not gui or not decompilerFrame then return end
    
    local yPos = 0
    for _, log in ipairs(decompilerLogs) do
        yPos = yPos + log.Size.Y.Offset
    end
    
    local logContainer = Instance.new("Frame")
    logContainer.Size = UDim2.new(1, -10, 0, 80)
    logContainer.Position = UDim2.new(0, 5, 0, yPos)
    logContainer.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    logContainer.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    logContainer.BorderSizePixel = 1
    logContainer.Parent = decompilerFrame
    
    local typeLabel = Instance.new("TextLabel")
    typeLabel.Size = UDim2.new(0, 80, 0, 20)
    typeLabel.Position = UDim2.new(0, 5, 0, 2)
    typeLabel.BackgroundTransparency = 1
    typeLabel.Text = scriptType
    typeLabel.TextColor3 = scriptType == "LocalScript" and Color3.new(0.2, 0.8, 0.2) or 
                          scriptType == "Script" and Color3.new(1, 0.5, 0.5) or 
                          Color3.new(0.8, 0.8, 0.2)
    typeLabel.TextSize = 11
    typeLabel.Font = Enum.Font.SourceSansBold
    typeLabel.TextXAlignment = Enum.TextXAlignment.Left
    typeLabel.Parent = logContainer
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -90, 0, 20)
    nameLabel.Position = UDim2.new(0, 90, 0, 2)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = scriptName
    nameLabel.TextColor3 = Color3.new(0.9, 0.9, 0.9)
    nameLabel.TextSize = 12
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = logContainer
    
    local pathLabel = Instance.new("TextLabel")
    pathLabel.Size = UDim2.new(1, -10, 0, 15)
    pathLabel.Position = UDim2.new(0, 5, 0, 22)
    pathLabel.BackgroundTransparency = 1
    pathLabel.Text = "Path: " .. scriptPath
    pathLabel.TextColor3 = Color3.new(0.6, 0.6, 0.6)
    pathLabel.TextSize = 10
    pathLabel.Font = Enum.Font.SourceSans
    pathLabel.TextXAlignment = Enum.TextXAlignment.Left
    pathLabel.TextTruncate = Enum.TextTruncate.AtEnd
    pathLabel.Parent = logContainer
    
    local sourceLabel = Instance.new("TextLabel")
    sourceLabel.Size = UDim2.new(1, -10, 0, 40)
    sourceLabel.Position = UDim2.new(0, 5, 0, 37)
    sourceLabel.BackgroundTransparency = 1
    local displaySource = source and (source:len() > 100 and source:sub(1, 100) .. "..." or source) or "Failed to decompile"
    sourceLabel.Text = "Source: " .. displaySource
    sourceLabel.TextColor3 = source and Color3.new(0.7, 0.9, 0.7) or Color3.new(1, 0.5, 0.5)
    sourceLabel.TextSize = 9
    sourceLabel.Font = Enum.Font.SourceSans
    sourceLabel.TextXAlignment = Enum.TextXAlignment.Left
    sourceLabel.TextYAlignment = Enum.TextYAlignment.Top
    sourceLabel.TextWrapped = true
    sourceLabel.Parent = logContainer
    
    logContainer.MouseEnter:Connect(function()
        logContainer.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    end)
    
    logContainer.MouseLeave:Connect(function()
        logContainer.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    end)
    
    logContainer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            showScriptInViewer(scriptName, scriptPath, source, scriptType)
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            local mousePos = UserInputService:GetMouseLocation()
            createScriptContextMenu(mousePos.X, mousePos.Y)
        end
    end)
    
    local function createScriptContextMenu(x, y)
        local existingMenu = gui:FindFirstChild("ScriptContextMenu")
        if existingMenu then
            existingMenu:Destroy()
        end
        
        local contextMenu = Instance.new("Frame")
        contextMenu.Name = "ScriptContextMenu"
        contextMenu.Size = UDim2.new(0, 150, 0, 120)
        contextMenu.Position = UDim2.new(0, x, 0, y)
        contextMenu.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
        contextMenu.BorderColor3 = Color3.new(0.3, 0.3, 0.3)
        contextMenu.BorderSizePixel = 1
        contextMenu.ZIndex = 15
        contextMenu.Parent = gui
        
        local function createContextButton(text, yPos, callback)
            local button = Instance.new("TextButton")
            button.Size = UDim2.new(1, -4, 0, 20)
            button.Position = UDim2.new(0, 2, 0, yPos)
            button.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            button.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
            button.BorderSizePixel = 1
            button.Text = text
            button.TextColor3 = Color3.new(0.9, 0.9, 0.9)
            button.TextSize = 11
            button.Font = Enum.Font.SourceSans
            button.ZIndex = 16
            button.Parent = contextMenu
            
            button.MouseEnter:Connect(function()
                button.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
            end)
            
            button.MouseLeave:Connect(function()
                button.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            end)
            
            button.MouseButton1Click:Connect(function()
                callback()
                contextMenu:Destroy()
            end)
            
            return button
        end
        
        createContextButton("View Script", 2, function()
            showScriptInViewer(scriptName, scriptPath, source, scriptType)
        end)
        
        createContextButton("Copy Source", 25, function()
            copyToClipboard(source or "Failed to decompile script")
            addLog("> Script source copied: " .. scriptName, Color3.new(0.5, 1, 0.5))
        end)
        
        createContextButton("Copy Path", 48, function()
            copyToClipboard(scriptPath)
            addLog("> Script path copied: " .. scriptPath, Color3.new(0.5, 1, 0.5))
        end)
        
        createContextButton("Get Calling Script", 71, function()
            local callingScript = getCallingScript()
            if callingScript then
                local callingScriptName = callingScript.Name
                local callingScriptPath = getPath(callingScript)
                local callingScriptType = callingScript.ClassName
                local callingSource = nil
                
                pcall(function()
                    if decompile then
                        callingSource = decompile(callingScript)
                    elseif getsource then
                        callingSource = getsource(callingScript)
                    elseif callingScript.Source then
                        callingSource = callingScript.Source
                    end
                end)
                
                addDecompilerLog(callingScriptName, callingScriptPath, callingSource, callingScriptType)
                addLog("> Added calling script: " .. callingScriptName, Color3.new(0.5, 1, 0.5))
            else
                addLog("> Could not get calling script", Color3.new(1, 0.8, 0.2))
            end
        end)
        
        createContextButton("Save Script", 94, function()
            if writefile then
                local fileName = scriptName:gsub("[^%w%-%_]", "_") .. ".lua"
                writefile(fileName, source or "Failed to decompile script")
                addLog("> Script saved as: " .. fileName, Color3.new(0.5, 1, 0.5))
            else
                addLog("> writefile not supported by executor", Color3.new(1, 0.8, 0.2))
            end
        end)
        
        local connection
        connection = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local mousePos = UserInputService:GetMouseLocation()
                local menuPos = contextMenu.AbsolutePosition
                local menuSize = contextMenu.AbsoluteSize
                
                if mousePos.X < menuPos.X or mousePos.X > menuPos.X + menuSize.X or
                   mousePos.Y < menuPos.Y or mousePos.Y > menuPos.Y + menuSize.Y then
                    contextMenu:Destroy()
                    connection:Disconnect()
                end
            end
        end)
        
        game:GetService("Debris"):AddItem(contextMenu, 10)
    end
    
    table.insert(decompilerLogs, logContainer)
    
    local totalHeight = 0
    for _, log in ipairs(decompilerLogs) do
        totalHeight = totalHeight + log.Size.Y.Offset
    end
    
    decompilerFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
    decompilerFrame.CanvasPosition = Vector2.new(0, decompilerFrame.CanvasSize.Y.Offset)
end

scanGameScripts = function()
    if not gui or not decompilerFrame or not decompilerContainer then return end
    
    local statusLabel = nil
    local decompilerControls = decompilerContainer:FindFirstChild("DecompilerControls")
    if decompilerControls then
        statusLabel = decompilerControls:FindFirstChild("StatusLabel")
    end
    
    if statusLabel then
        statusLabel.Text = "Scanning..."
        statusLabel.TextColor3 = Color3.new(1, 1, 0)
    end
    
    local scriptCount = 0
    local decompileCount = 0
    
    local function scanContainer(container, path)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
                scriptCount = scriptCount + 1
                local scriptPath = path .. "." .. child.Name
                local scriptType = child.ClassName
                
                local source = nil
                pcall(function()
                    if decompile then
                        source = decompile(child)
                        decompileCount = decompileCount + 1
                    elseif getsource then
                        source = getsource(child)
                        decompileCount = decompileCount + 1
                    elseif child.Source then
                        source = child.Source
                        decompileCount = decompileCount + 1
                    end
                end)
                
                addDecompilerLog(child.Name, scriptPath, source, scriptType)
                
                if statusLabel then
                    statusLabel.Text = "Found: " .. scriptCount .. " | Decompiled: " .. decompileCount
                end
                
                wait(0.01)
            end
            
            if child:GetChildren() and #child:GetChildren() > 0 then
                scanContainer(child, path .. "." .. child.Name)
            end
        end
    end
    
    spawn(function()
        scanContainer(game.Workspace, "game.Workspace")
        scanContainer(game.Players, "game.Players")
        scanContainer(game.Lighting, "game.Lighting")
        scanContainer(game.ReplicatedFirst, "game.ReplicatedFirst")
        scanContainer(game.ReplicatedStorage, "game.ReplicatedStorage")
        scanContainer(game.ServerScriptService, "game.ServerScriptService")
        scanContainer(game.ServerStorage, "game.ServerStorage")
        scanContainer(game.StarterGui, "game.StarterGui")
        scanContainer(game.StarterPack, "game.StarterPack")
        scanContainer(game.StarterPlayer, "game.StarterPlayer")
        
        if statusLabel then
            statusLabel.Text = "Scan complete! Found: " .. scriptCount .. " | Decompiled: " .. decompileCount
            statusLabel.TextColor3 = Color3.new(0.2, 0.8, 0.2)
        end
        
        addLog("> Decompiler scan complete! Found " .. scriptCount .. " scripts, decompiled " .. decompileCount, Color3.new(0.5, 1, 0.5))
    end)
end

createGUI = function()
    gui = Instance.new("ScreenGui")
    gui.Name = "RemoteSpyGUI"
    gui.ResetOnSpawn = false
    gui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    
    mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 700, 0, 450)
    mainFrame.Position = UDim2.new(0.5, -350, 0.5, -225)
    mainFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    mainFrame.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    mainFrame.BorderSizePixel = 1
    mainFrame.Parent = gui
    
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 25)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    titleBar.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    titleBar.BorderSizePixel = 1
    titleBar.Parent = mainFrame
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -50, 1, 0)
    title.Position = UDim2.new(0, 5, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Spy Tools [https://discord.gg/4THYgrRQd3]"
    title.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    title.TextSize = 14
    title.Font = Enum.Font.SourceSans
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = "CloseButton"
    closeBtn.Size = UDim2.new(0, 20, 0, 20)
    closeBtn.Position = UDim2.new(1, -23, 0, 2)
    closeBtn.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    closeBtn.BorderColor3 = Color3.new(0.3, 0.3, 0.3)
    closeBtn.BorderSizePixel = 1
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    closeBtn.TextSize = 12
    closeBtn.Font = Enum.Font.SourceSans
    closeBtn.Parent = titleBar
    makeButtonNonDraggable(closeBtn)
    
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, 0, 0, 30)
    tabBar.Position = UDim2.new(0, 0, 0, 25)
    tabBar.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    tabBar.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    tabBar.BorderSizePixel = 1
    tabBar.Parent = mainFrame
    
    local remoteSpyTab = Instance.new("TextButton")
    remoteSpyTab.Name = "RemoteSpyTab"
    remoteSpyTab.Size = UDim2.new(0, 100, 1, -3)
    remoteSpyTab.Position = UDim2.new(0, 5, 0, 0)
    remoteSpyTab.BackgroundColor3 = Color3.new(0.18, 0.18, 0.18)
    remoteSpyTab.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    remoteSpyTab.BorderSizePixel = 1
    remoteSpyTab.Text = "Remote Spy"
    remoteSpyTab.TextColor3 = Color3.new(0.9, 0.9, 0.9)
    remoteSpyTab.TextSize = 12
    remoteSpyTab.Font = Enum.Font.SourceSans
    remoteSpyTab.Parent = tabBar
    makeButtonNonDraggable(remoteSpyTab)
    
    local remoteSpyHighlight = Instance.new("Frame")
    remoteSpyHighlight.Name = "Highlight"
    remoteSpyHighlight.Size = UDim2.new(1, 0, 0, 2)
    remoteSpyHighlight.Position = UDim2.new(0, 0, 0, 0)
    remoteSpyHighlight.BackgroundColor3 = Color3.new(1, 0.2, 0.2)
    remoteSpyHighlight.BorderSizePixel = 0
    remoteSpyHighlight.Parent = remoteSpyTab
    
    local httpSpyTab = Instance.new("TextButton")
    httpSpyTab.Name = "HttpSpyTab"
    httpSpyTab.Size = UDim2.new(0, 80, 1, -3)
    httpSpyTab.Position = UDim2.new(0, 110, 0, 0)
    httpSpyTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    httpSpyTab.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    httpSpyTab.BorderSizePixel = 1
    httpSpyTab.Text = "HttpSpy"
    httpSpyTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    httpSpyTab.TextSize = 12
    httpSpyTab.Font = Enum.Font.SourceSans
    httpSpyTab.Parent = tabBar
    makeButtonNonDraggable(httpSpyTab)
    
    local httpSpyHighlight = Instance.new("Frame")
    httpSpyHighlight.Name = "Highlight"
    httpSpyHighlight.Size = UDim2.new(1, 0, 0, 2)
    httpSpyHighlight.Position = UDim2.new(0, 0, 0, 0)
    httpSpyHighlight.BackgroundColor3 = Color3.new(1, 0.2, 0.2)
    httpSpyHighlight.BorderSizePixel = 0
    httpSpyHighlight.Visible = false
    httpSpyHighlight.Parent = httpSpyTab
    
    local decompilerTab = Instance.new("TextButton")
    decompilerTab.Name = "DecompilerTab"
    decompilerTab.Size = UDim2.new(0, 100, 1, -3)
    decompilerTab.Position = UDim2.new(0, 195, 0, 0)
    decompilerTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    decompilerTab.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    decompilerTab.BorderSizePixel = 1
    decompilerTab.Text = "Decompiler"
    decompilerTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    decompilerTab.TextSize = 12
    decompilerTab.Font = Enum.Font.SourceSans
    decompilerTab.Parent = tabBar
    makeButtonNonDraggable(decompilerTab)
    
    local decompilerHighlight = Instance.new("Frame")
    decompilerHighlight.Name = "Highlight"
    decompilerHighlight.Size = UDim2.new(1, 0, 0, 2)
    decompilerHighlight.Position = UDim2.new(0, 0, 0, 0)
    decompilerHighlight.BackgroundColor3 = Color3.new(1, 0.2, 0.2)
    decompilerHighlight.BorderSizePixel = 0
    decompilerHighlight.Visible = false
    decompilerHighlight.Parent = decompilerTab
    
    local controlPanel = Instance.new("Frame")
    controlPanel.Name = "ControlPanel"
    controlPanel.Size = UDim2.new(0.7, -10, 0, 25)
    controlPanel.Position = UDim2.new(0, 5, 0, 60)
    controlPanel.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    controlPanel.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    controlPanel.BorderSizePixel = 1
    controlPanel.Parent = mainFrame
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(0, 60, 1, 0)
    statusLabel.Position = UDim2.new(0, 5, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "ACTIVE"
    statusLabel.TextColor3 = Color3.new(0.2, 0.8, 0.2)
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = controlPanel
    
    local statsLabel = Instance.new("TextLabel")
    statsLabel.Name = "StatsLabel"
    statsLabel.Size = UDim2.new(1, -70, 1, 0)
    statsLabel.Position = UDim2.new(0, 70, 0, 0)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Text = "Fires: 0 | Invokes: 0 | Remotes: 0"
    statsLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    statsLabel.TextSize = 11
    statsLabel.Font = Enum.Font.SourceSans
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.Parent = controlPanel
    
    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0.3, -5, 1, -95)
    sidebar.Position = UDim2.new(0.7, 5, 0, 60)
    sidebar.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    sidebar.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    sidebar.BorderSizePixel = 1
    sidebar.Parent = mainFrame
    
    local searchBox = Instance.new("TextBox")
    searchBox.Name = "SearchBox"
    searchBox.Size = UDim2.new(1, -10, 0, 20)
    searchBox.Position = UDim2.new(0, 5, 0, 5)
    searchBox.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    searchBox.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    searchBox.BorderSizePixel = 1
    searchBox.Text = ""
    searchBox.PlaceholderText = "Search remotes..."
    searchBox.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    searchBox.PlaceholderColor3 = Color3.new(0.5, 0.5, 0.5)
    searchBox.TextSize = 12
    searchBox.Font = Enum.Font.SourceSans
    searchBox.Parent = sidebar
    makeButtonNonDraggable(searchBox)
    
    local selectedInfo = Instance.new("TextLabel")
    selectedInfo.Name = "SelectedInfo"
    selectedInfo.Size = UDim2.new(1, -10, 0, 50)
    selectedInfo.Position = UDim2.new(0, 5, 0, 30)
    selectedInfo.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    selectedInfo.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    selectedInfo.BorderSizePixel = 1
    selectedInfo.Text = "Click a remote to select"
    selectedInfo.TextColor3 = Color3.new(0.6, 0.6, 0.6)
    selectedInfo.TextSize = 10
    selectedInfo.Font = Enum.Font.SourceSans
    selectedInfo.TextXAlignment = Enum.TextXAlignment.Left
    selectedInfo.TextYAlignment = Enum.TextYAlignment.Top
    selectedInfo.TextWrapped = true
    selectedInfo.Parent = sidebar
    
    local copyPathBtn, copyArgsBtn, copyCodeBtn, runBtn, exportBtn, clearBtn, settingsBtn, toggleBtn, blockBtn = Instance.new("TextButton"), Instance.new("TextButton"), Instance.new("TextButton"), Instance.new("TextButton"), Instance.new("TextButton"), Instance.new("TextButton"), Instance.new("TextButton"), Instance.new("TextButton"), Instance.new("TextButton")
    
    copyPathBtn.Name = "CopyPathBtn"
    copyPathBtn.Size = UDim2.new(1, -10, 0, 20)
    copyPathBtn.Position = UDim2.new(0, 5, 0, 85)
    copyPathBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    copyPathBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    copyPathBtn.BorderSizePixel = 1
    copyPathBtn.Text = "Copy Path"
    copyPathBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    copyPathBtn.TextSize = 11
    copyPathBtn.Font = Enum.Font.SourceSans
    copyPathBtn.Parent = sidebar
    makeButtonNonDraggable(copyPathBtn)
    
    copyArgsBtn.Name = "CopyArgsBtn"
    copyArgsBtn.Size = UDim2.new(1, -10, 0, 20)
    copyArgsBtn.Position = UDim2.new(0, 5, 0, 110)
    copyArgsBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    copyArgsBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    copyArgsBtn.BorderSizePixel = 1
    copyArgsBtn.Text = "Copy Arguments"
    copyArgsBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    copyArgsBtn.TextSize = 11
    copyArgsBtn.Font = Enum.Font.SourceSans
    copyArgsBtn.Parent = sidebar
    makeButtonNonDraggable(copyArgsBtn)
    
    copyCodeBtn.Name = "CopyCodeBtn"
    copyCodeBtn.Size = UDim2.new(1, -10, 0, 20)
    copyCodeBtn.Position = UDim2.new(0, 5, 0, 135)
    copyCodeBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    copyCodeBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    copyCodeBtn.BorderSizePixel = 1
    copyCodeBtn.Text = "Copy Code"
    copyCodeBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    copyCodeBtn.TextSize = 11
    copyCodeBtn.Font = Enum.Font.SourceSans
    copyCodeBtn.Parent = sidebar
    makeButtonNonDraggable(copyCodeBtn)
    
    runBtn.Name = "RunBtn"
    runBtn.Size = UDim2.new(1, -10, 0, 20)
    runBtn.Position = UDim2.new(0, 5, 0, 160)
    runBtn.BackgroundColor3 = Color3.new(0.1, 0.2, 0.1)
    runBtn.BorderColor3 = Color3.new(0.2, 0.3, 0.2)
    runBtn.BorderSizePixel = 1
    runBtn.Text = "Run Remote"
    runBtn.TextColor3 = Color3.new(0.7, 1, 0.7)
    runBtn.TextSize = 11
    runBtn.Font = Enum.Font.SourceSans
    runBtn.Parent = sidebar
    makeButtonNonDraggable(runBtn)
    
    exportBtn.Name = "ExportBtn"
    exportBtn.Size = UDim2.new(1, -10, 0, 20)
    exportBtn.Position = UDim2.new(0, 5, 0, 185)
    exportBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    exportBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    exportBtn.BorderSizePixel = 1
    exportBtn.Text = "Export Data"
    exportBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    exportBtn.TextSize = 11
    exportBtn.Font = Enum.Font.SourceSans
    exportBtn.Parent = sidebar
    makeButtonNonDraggable(exportBtn)
    
    blockBtn.Name = "BlockBtn"
    blockBtn.Size = UDim2.new(1, -10, 0, 20)
    blockBtn.Position = UDim2.new(0, 5, 0, 210)
    blockBtn.BackgroundColor3 = Color3.new(0.2, 0.1, 0.1)
    blockBtn.BorderColor3 = Color3.new(0.3, 0.2, 0.2)
    blockBtn.BorderSizePixel = 1
    blockBtn.Text = "Block Remote"
    blockBtn.TextColor3 = Color3.new(1, 0.7, 0.7)
    blockBtn.TextSize = 11
    blockBtn.Font = Enum.Font.SourceSans
    blockBtn.Parent = sidebar
    makeButtonNonDraggable(blockBtn)
    
    settingsBtn.Name = "SettingsBtn"
    settingsBtn.Size = UDim2.new(1, -10, 0, 20)
    settingsBtn.Position = UDim2.new(0, 5, 0, 235)
    settingsBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    settingsBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    settingsBtn.BorderSizePixel = 1
    settingsBtn.Text = "Settings"
    settingsBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    settingsBtn.TextSize = 11
    settingsBtn.Font = Enum.Font.SourceSans
    settingsBtn.Parent = sidebar
    makeButtonNonDraggable(settingsBtn)
    
    toggleBtn.Name = "ToggleBtn"
    toggleBtn.Size = UDim2.new(1, -10, 0, 20)
    toggleBtn.Position = UDim2.new(0, 5, 1, -50)
    toggleBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    toggleBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    toggleBtn.BorderSizePixel = 1
    toggleBtn.Text = "Stop Monitoring"
    toggleBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    toggleBtn.TextSize = 11
    toggleBtn.Font = Enum.Font.SourceSans
    toggleBtn.Parent = sidebar
    makeButtonNonDraggable(toggleBtn)
    
    clearBtn.Name = "ClearBtn"
    clearBtn.Size = UDim2.new(1, -10, 0, 20)
    clearBtn.Position = UDim2.new(0, 5, 1, -75)
    clearBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    clearBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    clearBtn.BorderSizePixel = 1
    clearBtn.Text = "Clear Logs"
    clearBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    clearBtn.TextSize = 11
    clearBtn.Font = Enum.Font.SourceSans
    clearBtn.Parent = sidebar
    makeButtonNonDraggable(clearBtn)
    
    local logContainer = Instance.new("Frame")
    logContainer.Name = "LogContainer"
    logContainer.Size = UDim2.new(0.7, -10, 1, -95)
    logContainer.Position = UDim2.new(0, 5, 0, 90)
    logContainer.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    logContainer.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    logContainer.BorderSizePixel = 1
    logContainer.Parent = mainFrame
    
    logFrame = Instance.new("ScrollingFrame")
    logFrame.Name = "LogFrame"
    logFrame.Size = UDim2.new(1, -5, 1, -5)
    logFrame.Position = UDim2.new(0, 2, 0, 2)
    logFrame.BackgroundTransparency = 1
    logFrame.BorderSizePixel = 0
    logFrame.ScrollBarThickness = 8
    logFrame.ScrollBarImageColor3 = Color3.new(0.3, 0.3, 0.3)
    logFrame.ScrollBarImageTransparency = 0
    logFrame.Parent = logContainer
    
    local httpLogContainer = Instance.new("Frame")
    httpLogContainer.Name = "HttpLogContainer"
    httpLogContainer.Size = UDim2.new(0.7, -10, 1, -95)
    httpLogContainer.Position = UDim2.new(0, 5, 0, 90)
    httpLogContainer.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    httpLogContainer.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    httpLogContainer.BorderSizePixel = 1
    httpLogContainer.Visible = false
    httpLogContainer.Parent = mainFrame
    
    httpLogFrame = Instance.new("ScrollingFrame")
    httpLogFrame.Name = "HttpLogFrame"
    httpLogFrame.Size = UDim2.new(1, -5, 1, -5)
    httpLogFrame.Position = UDim2.new(0, 2, 0, 2)
    httpLogFrame.BackgroundTransparency = 1
    httpLogFrame.BorderSizePixel = 0
    httpLogFrame.ScrollBarThickness = 8
    httpLogFrame.ScrollBarImageColor3 = Color3.new(0.3, 0.3, 0.3)
    httpLogFrame.ScrollBarImageTransparency = 0
    httpLogFrame.Parent = httpLogContainer
    
    local httpInfoLabel = Instance.new("TextLabel")
    httpInfoLabel.Size = UDim2.new(1, -20, 0, 100)
    httpInfoLabel.Position = UDim2.new(0, 10, 0, 10)
    httpInfoLabel.BackgroundTransparency = 1
    httpInfoLabel.Text = "HTTP Spy Monitor\n\nThis tab monitors HTTP requests made through:\n• syn.request\n• request\n• http_request\n\nHTTP requests will appear here when detected."
    httpInfoLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    httpInfoLabel.TextSize = 12
    httpInfoLabel.Font = Enum.Font.SourceSans
    httpInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    httpInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
    httpInfoLabel.TextWrapped = true
    httpInfoLabel.Parent = httpLogFrame
    
    decompilerContainer = Instance.new("Frame")
    decompilerContainer.Name = "DecompilerContainer"
    decompilerContainer.Size = UDim2.new(1, -10, 1, -95)
    decompilerContainer.Position = UDim2.new(0, 5, 0, 90)
    decompilerContainer.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    decompilerContainer.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    decompilerContainer.BorderSizePixel = 1
    decompilerContainer.Visible = false
    decompilerContainer.Parent = mainFrame
    
    local decompilerControls = Instance.new("Frame")
    decompilerControls.Name = "DecompilerControls"
    decompilerControls.Size = UDim2.new(1, -10, 0, 30)
    decompilerControls.Position = UDim2.new(0, 5, 0, 5)
    decompilerControls.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    decompilerControls.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    decompilerControls.BorderSizePixel = 1
    decompilerControls.Parent = decompilerContainer
    
    local scanButton = Instance.new("TextButton")
    scanButton.Name = "ScanButton"
    scanButton.Size = UDim2.new(0, 80, 1, -4)
    scanButton.Position = UDim2.new(0, 5, 0, 2)
    scanButton.BackgroundColor3 = Color3.new(0.2, 0.6, 0.2)
    scanButton.BorderColor3 = Color3.new(0.3, 0.7, 0.3)
    scanButton.BorderSizePixel = 1
    scanButton.Text = "Scan Game"
    scanButton.TextColor3 = Color3.new(1, 1, 1)
    scanButton.TextSize = 12
    scanButton.Font = Enum.Font.SourceSans
    scanButton.Parent = decompilerControls
    makeButtonNonDraggable(scanButton)
    
    local clearDecompilerButton = Instance.new("TextButton")
    clearDecompilerButton.Name = "ClearDecompilerButton"
    clearDecompilerButton.Size = UDim2.new(0, 60, 1, -4)
    clearDecompilerButton.Position = UDim2.new(0, 90, 0, 2)
    clearDecompilerButton.BackgroundColor3 = Color3.new(0.6, 0.2, 0.2)
    clearDecompilerButton.BorderColor3 = Color3.new(0.7, 0.3, 0.3)
    clearDecompilerButton.BorderSizePixel = 1
    clearDecompilerButton.Text = "Clear"
    clearDecompilerButton.TextColor3 = Color3.new(1, 1, 1)
    clearDecompilerButton.TextSize = 12
    clearDecompilerButton.Font = Enum.Font.SourceSans
    clearDecompilerButton.Parent = decompilerControls
    makeButtonNonDraggable(clearDecompilerButton)
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, -160, 1, 0)
    statusLabel.Position = UDim2.new(0, 155, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Ready to scan"
    statusLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = decompilerControls
    
    decompilerFrame = Instance.new("ScrollingFrame")
    decompilerFrame.Name = "DecompilerFrame"
    decompilerFrame.Size = UDim2.new(1, -10, 1, -45)
    decompilerFrame.Position = UDim2.new(0, 5, 0, 40)
    decompilerFrame.BackgroundTransparency = 1
    decompilerFrame.BorderSizePixel = 0
    decompilerFrame.ScrollBarThickness = 8
    decompilerFrame.ScrollBarImageColor3 = Color3.new(0.3, 0.3, 0.3)
    decompilerFrame.ScrollBarImageTransparency = 0
    decompilerFrame.Parent = decompilerContainer
    

    local dragging, dragStart, startPos = false, nil, nil
    
    local function makeDraggable(frame, dragFrame)
        dragFrame = dragFrame or frame
        local originalTransparency = dragFrame.BackgroundTransparency
        
        dragFrame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and not buttonInteraction then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                

                if dragFrame.BackgroundTransparency < 1 then
                    dragFrame.BackgroundTransparency = math.max(0, dragFrame.BackgroundTransparency - 0.1)
                end
            end
        end)
        
        dragFrame.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
        
        dragFrame.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false

                dragFrame.BackgroundTransparency = originalTransparency
            end
        end)
        

        dragFrame.MouseEnter:Connect(function()
            if not dragging and dragFrame.BackgroundTransparency < 1 then
                dragFrame.BackgroundTransparency = math.max(0, dragFrame.BackgroundTransparency - 0.05)
            end
        end)
        
        dragFrame.MouseLeave:Connect(function()
            if not dragging then
                dragFrame.BackgroundTransparency = originalTransparency
            end
        end)
    end
    

    makeDraggable(mainFrame, titleBar)
    

    makeDraggable(mainFrame, controlPanel)
    

    local sidebarDragging = false
    
    sidebar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not buttonInteraction then
            sidebarDragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    
    sidebar.InputChanged:Connect(function(input)
        if sidebarDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    sidebar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sidebarDragging = false
        end
    end)
    

    local logContainerDragging = false
    
    logContainer.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not buttonInteraction then
            logContainerDragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    
    logContainer.InputChanged:Connect(function(input)
        if logContainerDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    logContainer.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            logContainerDragging = false
        end
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        _G.RemoteSpyClose()
    end)
    
    local function switchTab(tabName)
        currentTab = tabName
        if tabName == "RemoteSpy" then
            remoteSpyTab.BackgroundColor3 = Color3.new(0.18, 0.18, 0.18)
            remoteSpyTab.TextColor3 = Color3.new(0.9, 0.9, 0.9)
            remoteSpyHighlight.Visible = true
            httpSpyTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            httpSpyTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
            httpSpyHighlight.Visible = false
            decompilerTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            decompilerTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
            decompilerHighlight.Visible = false
            logContainer.Visible = true
            httpLogContainer.Visible = false
            decompilerContainer.Visible = false
            controlPanel.Visible = true
        elseif tabName == "HttpSpy" then
            httpSpyTab.BackgroundColor3 = Color3.new(0.18, 0.18, 0.18)
            httpSpyTab.TextColor3 = Color3.new(0.9, 0.9, 0.9)
            httpSpyHighlight.Visible = true
            remoteSpyTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            remoteSpyTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
            remoteSpyHighlight.Visible = false
            decompilerTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            decompilerTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
            decompilerHighlight.Visible = false
            logContainer.Visible = false
            httpLogContainer.Visible = true
            decompilerContainer.Visible = false
            controlPanel.Visible = false
        elseif tabName == "Decompiler" then
            decompilerTab.BackgroundColor3 = Color3.new(0.18, 0.18, 0.18)
            decompilerTab.TextColor3 = Color3.new(0.9, 0.9, 0.9)
            decompilerHighlight.Visible = true
            remoteSpyTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            remoteSpyTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
            remoteSpyHighlight.Visible = false
            httpSpyTab.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
            httpSpyTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
            httpSpyHighlight.Visible = false
            logContainer.Visible = false
            httpLogContainer.Visible = false
            decompilerContainer.Visible = true
            controlPanel.Visible = false
        end
    end
    
    remoteSpyTab.MouseButton1Click:Connect(function()
        switchTab("RemoteSpy")
    end)
    
    httpSpyTab.MouseButton1Click:Connect(function()
        switchTab("HttpSpy")
    end)
    
    decompilerTab.MouseButton1Click:Connect(function()
        switchTab("Decompiler")
    end)
    
    scanButton.MouseButton1Click:Connect(function()
        scanGameScripts()
    end)
    
    clearDecompilerButton.MouseButton1Click:Connect(function()
        for _, log in ipairs(decompilerLogs) do
            log:Destroy()
        end
        decompilerLogs = {}
        decompilerFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        
        local statusLabel = nil
        local decompilerControls = decompilerContainer:FindFirstChild("DecompilerControls")
        if decompilerControls then
            statusLabel = decompilerControls:FindFirstChild("StatusLabel")
        end
        
        if statusLabel then
            statusLabel.Text = "Ready to scan"
            statusLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
        end
        addLog("> Decompiler logs cleared!", Color3.new(0.5, 1, 0.5))
    end)
    
    local buttons = {
        copyPathBtn = copyPathBtn,
        copyArgsBtn = copyArgsBtn,
        copyCodeBtn = copyCodeBtn,
        runBtn = runBtn,
        clearBtn = clearBtn,
        exportBtn = exportBtn,
        settingsBtn = settingsBtn,
        toggleBtn = toggleBtn,
        blockBtn = blockBtn
    }
    
    return {
        statsLabel = statsLabel,
        statusLabel = statusLabel,
        selectedInfo = selectedInfo,
        searchBox = searchBox,
        buttons = buttons
    }
end

local uiElements = {}

createSettingsFrame = function()
    settingsFrame = Instance.new("Frame")
    settingsFrame.Name = "SettingsFrame"
    settingsFrame.Size = UDim2.new(0, 280, 0, 300)
    settingsFrame.Position = UDim2.new(0.5, -140, 0.5, -150)
    settingsFrame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    settingsFrame.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    settingsFrame.BorderSizePixel = 1
    settingsFrame.Visible = false
    settingsFrame.ZIndex = 10
    settingsFrame.Parent = gui
    
    local settingsTitle = Instance.new("Frame")
    settingsTitle.Size = UDim2.new(1, 0, 0, 25)
    settingsTitle.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    settingsTitle.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    settingsTitle.BorderSizePixel = 1
    settingsTitle.ZIndex = 11
    settingsTitle.Parent = settingsFrame
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -25, 1, 0)
    titleLabel.Position = UDim2.new(0, 5, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "Settings & Info [by discord 'skondoooo92']"
    titleLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    titleLabel.TextSize = 14
    titleLabel.Font = Enum.Font.SourceSans
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 12
    titleLabel.Parent = settingsTitle
    
    local closeSettings = Instance.new("TextButton")
    closeSettings.Size = UDim2.new(0, 20, 0, 20)
    closeSettings.Position = UDim2.new(1, -23, 0, 2)
    closeSettings.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    closeSettings.BorderColor3 = Color3.new(0.3, 0.3, 0.3)
    closeSettings.BorderSizePixel = 1
    closeSettings.Text = "X"
    closeSettings.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    closeSettings.TextSize = 12
    closeSettings.Font = Enum.Font.SourceSans
    closeSettings.ZIndex = 12
    closeSettings.Parent = settingsTitle
    makeButtonNonDraggable(closeSettings)
    
    local function createButton(text, yPos, callback)
        local button = Instance.new("TextButton")
        button.Name = text:gsub(" ", "") .. "Btn"
        button.Size = UDim2.new(1, -20, 0, 25)
        button.Position = UDim2.new(0, 10, 0, yPos)
        button.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
        button.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
        button.BorderSizePixel = 1
        button.Text = text
        button.TextColor3 = Color3.new(0.8, 0.8, 0.8)
        button.TextSize = 12
        button.Font = Enum.Font.SourceSans
        button.ZIndex = 12
        button.Parent = settingsFrame
        
        button.MouseEnter:Connect(function()
            button.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
        end)
        
        button.MouseLeave:Connect(function()
            button.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
        end)
        
        button.MouseButton1Click:Connect(callback)
        return button
    end
    
    local function createToggle(text, yPos, defaultValue, callback)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -20, 0, 25)
        frame.Position = UDim2.new(0, 10, 0, yPos)
        frame.BackgroundTransparency = 1
        frame.ZIndex = 11
        frame.Parent = settingsFrame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0.7, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.new(0.8, 0.8, 0.8)
        label.TextSize = 12
        label.Font = Enum.Font.SourceSans
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 12
        label.Parent = frame
        
        local toggle = Instance.new("TextButton")
        toggle.Size = UDim2.new(0, 60, 0, 20)
        toggle.Position = UDim2.new(1, -65, 0, 2)
        toggle.BackgroundColor3 = defaultValue and Color3.new(0.2, 0.6, 0.2) or Color3.new(0.6, 0.2, 0.2)
        toggle.BorderColor3 = Color3.new(0.3, 0.3, 0.3)
        toggle.BorderSizePixel = 1
        toggle.Text = defaultValue and "ON" or "OFF"
        toggle.TextColor3 = Color3.new(1, 1, 1)
        toggle.TextSize = 11
        toggle.Font = Enum.Font.SourceSans
        toggle.ZIndex = 12
        toggle.Parent = frame
        
        toggle.MouseButton1Click:Connect(function()
            defaultValue = not defaultValue
            toggle.BackgroundColor3 = defaultValue and Color3.new(0.2, 0.6, 0.2) or Color3.new(0.6, 0.2, 0.2)
            toggle.Text = defaultValue and "ON" or "OFF"
            callback(defaultValue)
        end)
        
        return toggle
    end
    

    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -20, 0, 20)
    infoLabel.Position = UDim2.new(0, 10, 0, 35)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "━━━━━━━━━━━━ INFO ━━━━━━━━━━━━"
    infoLabel.TextColor3 = Color3.new(0.6, 0.6, 0.6)
    infoLabel.TextSize = 11
    infoLabel.Font = Enum.Font.SourceSans
    infoLabel.TextXAlignment = Enum.TextXAlignment.Center
    infoLabel.ZIndex = 12
    infoLabel.Parent = settingsFrame
    
    createButton("> Copy Discord Link", 60, function()
        copyToClipboard("https://discord.gg/4THYgrRQd3")
        addLog("> Discord link copied!", Color3.new(0.5, 1, 0.5))
    end)
    
    createButton("> Copy Website Link", 90, function()
        copyToClipboard("https://remotespy.dev")
        addLog("> Website link copied!", Color3.new(0.5, 1, 0.5))
    end)
    

    local settingsLabel = Instance.new("TextLabel")
    settingsLabel.Size = UDim2.new(1, -20, 0, 20)
    settingsLabel.Position = UDim2.new(0, 10, 0, 125)
    settingsLabel.BackgroundTransparency = 1
    settingsLabel.Text = "━━━━━━━━━━ SETTINGS ━━━━━━━━━━"
    settingsLabel.TextColor3 = Color3.new(0.6, 0.6, 0.6)
    settingsLabel.TextSize = 11
    settingsLabel.Font = Enum.Font.SourceSans
    settingsLabel.TextXAlignment = Enum.TextXAlignment.Center
    settingsLabel.ZIndex = 12
    settingsLabel.Parent = settingsFrame
    
    createToggle("Show Arguments", 150, showArgs, function(val) 
        showArgs = val 
        addLog("Show Arguments: " .. (val and "ON" or "OFF"), Color3.new(1, 1, 0))
    end)
    
    createToggle("Show Timestamps", 180, showTimestamps, function(val) 
        showTimestamps = val 
        addLog("Show Timestamps: " .. (val and "ON" or "OFF"), Color3.new(1, 1, 0))
    end)
    
    createToggle("Mini Executor", 210, miniExecutorVisible, function(val) 
        miniExecutorVisible = val
        if miniExecutorVisible then
            createMiniExecutor()
        else
            if miniExecutor then
                miniExecutor:Destroy()
                miniExecutor = nil
            end
        end
        addLog("Mini Executor: " .. (val and "ON" or "OFF"), Color3.new(1, 1, 0))
    end)
    

    local maxLogsFrame = Instance.new("Frame")
    maxLogsFrame.Size = UDim2.new(1, -20, 0, 25)
    maxLogsFrame.Position = UDim2.new(0, 10, 0, 240)
    maxLogsFrame.BackgroundTransparency = 1
    maxLogsFrame.ZIndex = 11
    maxLogsFrame.Parent = settingsFrame
    
    local maxLogsLabel = Instance.new("TextLabel")
    maxLogsLabel.Size = UDim2.new(0.6, 0, 1, 0)
    maxLogsLabel.BackgroundTransparency = 1
    maxLogsLabel.Text = "Max Logs:"
    maxLogsLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    maxLogsLabel.TextSize = 12
    maxLogsLabel.Font = Enum.Font.SourceSans
    maxLogsLabel.TextXAlignment = Enum.TextXAlignment.Left
    maxLogsLabel.ZIndex = 12
    maxLogsLabel.Parent = maxLogsFrame
    
    local maxLogsBox = Instance.new("TextBox")
    maxLogsBox.Size = UDim2.new(0, 80, 0, 20)
    maxLogsBox.Position = UDim2.new(1, -85, 0, 2)
    maxLogsBox.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    maxLogsBox.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    maxLogsBox.BorderSizePixel = 1
    maxLogsBox.Text = tostring(maxLogs)
    maxLogsBox.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    maxLogsBox.TextSize = 11
    maxLogsBox.Font = Enum.Font.SourceSans
    maxLogsBox.ZIndex = 12
    maxLogsBox.Parent = maxLogsFrame
    
    maxLogsBox.FocusLost:Connect(function()
        local num = tonumber(maxLogsBox.Text)
        if num and num > 0 and num <= 2000 then
            maxLogs = num
            addLog("Max logs set to: " .. num, Color3.new(1, 1, 0))
        else
            maxLogsBox.Text = tostring(maxLogs)
        end
    end)
    
    closeSettings.MouseButton1Click:Connect(function()
        settingsFrame.Visible = false
    end)
    

    local settingsDragging, settingsDragStart, settingsStartPos = false, nil, nil
    
    settingsFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not buttonInteraction then
            settingsDragging = true
            settingsDragStart = input.Position
            settingsStartPos = settingsFrame.Position
        end
    end)
    
    settingsFrame.InputChanged:Connect(function(input)
        if settingsDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - settingsDragStart
            settingsFrame.Position = UDim2.new(settingsStartPos.X.Scale, settingsStartPos.X.Offset + delta.X, settingsStartPos.Y.Scale, settingsStartPos.Y.Offset + delta.Y)
        end
    end)
    
    settingsFrame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            settingsDragging = false
        end
    end)
end

createMiniExecutor = function()
    if miniExecutor then return end
    
    miniExecutor = Instance.new("Frame")
    miniExecutor.Name = "MiniExecutor"
    miniExecutor.Size = UDim2.new(0, 250, 0, 150)
    miniExecutor.Position = UDim2.new(1, -260, 1, -160)
    miniExecutor.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    miniExecutor.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    miniExecutor.BorderSizePixel = 1
    miniExecutor.ZIndex = 8
    miniExecutor.Parent = gui
    
    local execTitle = Instance.new("Frame")
    execTitle.Size = UDim2.new(1, 0, 0, 20)
    execTitle.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    execTitle.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    execTitle.BorderSizePixel = 1
    execTitle.ZIndex = 9
    execTitle.Parent = miniExecutor
    
    local execLabel = Instance.new("TextLabel")
    execLabel.Size = UDim2.new(1, -25, 1, 0)
    execLabel.Position = UDim2.new(0, 5, 0, 0)
    execLabel.BackgroundTransparency = 1
    execLabel.Text = "Mini Executor"
    execLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    execLabel.TextSize = 12
    execLabel.Font = Enum.Font.SourceSans
    execLabel.TextXAlignment = Enum.TextXAlignment.Left
    execLabel.ZIndex = 10
    execLabel.Parent = execTitle
    
    local closeExec = Instance.new("TextButton")
    closeExec.Size = UDim2.new(0, 18, 0, 18)
    closeExec.Position = UDim2.new(1, -20, 0, 1)
    closeExec.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    closeExec.BorderColor3 = Color3.new(0.3, 0.3, 0.3)
    closeExec.BorderSizePixel = 1
    closeExec.Text = "X"
    closeExec.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    closeExec.TextSize = 10
    closeExec.Font = Enum.Font.SourceSans
    closeExec.ZIndex = 10
    closeExec.Parent = execTitle
    
    local codeBox = Instance.new("TextBox")
    codeBox.Size = UDim2.new(1, -10, 1, -50)
    codeBox.Position = UDim2.new(0, 5, 0, 25)
    codeBox.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    codeBox.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    codeBox.BorderSizePixel = 1
    codeBox.Text = "-- Enter your script here\nprint('Hello from Mini Executor!')"
    codeBox.PlaceholderText = "Enter Lua code here..."
    codeBox.TextColor3 = Color3.new(0.9, 0.9, 0.9)
    codeBox.PlaceholderColor3 = Color3.new(0.5, 0.5, 0.5)
    codeBox.TextSize = 11
    codeBox.Font = Enum.Font.SourceSans
    codeBox.TextXAlignment = Enum.TextXAlignment.Left
    codeBox.TextYAlignment = Enum.TextYAlignment.Top
    codeBox.MultiLine = true
    codeBox.TextWrapped = true
    codeBox.ClearTextOnFocus = false
    codeBox.ZIndex = 9
    codeBox.Parent = miniExecutor
    
    local execBtn = Instance.new("TextButton")
    execBtn.Size = UDim2.new(0, 60, 0, 20)
    execBtn.Position = UDim2.new(1, -65, 1, -25)
    execBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    execBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    execBtn.BorderSizePixel = 1
    execBtn.Text = "Execute"
    execBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    execBtn.TextSize = 11
    execBtn.Font = Enum.Font.SourceSans
    execBtn.ZIndex = 9
    execBtn.Parent = miniExecutor
    
    local clearBtn = Instance.new("TextButton")
    clearBtn.Size = UDim2.new(0, 50, 0, 20)
    clearBtn.Position = UDim2.new(1, -130, 1, -25)
    clearBtn.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
    clearBtn.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
    clearBtn.BorderSizePixel = 1
    clearBtn.Text = "Clear"
    clearBtn.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    clearBtn.TextSize = 11
    clearBtn.Font = Enum.Font.SourceSans
    clearBtn.ZIndex = 9
    clearBtn.Parent = miniExecutor
    

    local dragging, dragStart, startPos = false, nil, nil
    
    execTitle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = miniExecutor.Position
        end
    end)
    
    execTitle.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            miniExecutor.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    execTitle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    execBtn.MouseButton1Click:Connect(function()
        pcall(function()
            local code = codeBox.Text
            if code and code:len() > 0 then
                local success, error = pcall(function()
                    loadstring(code)()
                end)
                if success then
                    addLog("> Mini Executor: Code executed successfully", Color3.new(0.2, 0.8, 0.2))
                else
                    addLog("> Mini Executor Error: " .. tostring(error), Color3.new(1, 0.5, 0.5))
                end
            end
        end)
    end)
    
    clearBtn.MouseButton1Click:Connect(function()
        codeBox.Text = ""
    end)
    
    closeExec.MouseButton1Click:Connect(function()
        miniExecutorVisible = false
        miniExecutor:Destroy()
        miniExecutor = nil
        addLog("Mini Executor closed", Color3.new(1, 1, 0))
    end)
end

copyToClipboard = function(text)
    if setclipboard then
        setclipboard(text)
        addLog("> Copied to clipboard: " .. (text:len() > 50 and text:sub(1, 50) .. "..." or text), Color3.new(0.5, 1, 0.5))
    else
        addLog("> Clipboard not supported by executor", Color3.new(1, 0.5, 0.5))
    end
end

updateStats = function()
    if uiElements.statsLabel then
        local uniqueCount = 0
        for _ in pairs(stats.uniqueRemotes) do
            uniqueCount = uniqueCount + 1
        end
        uiElements.statsLabel.Text = "Fires: " .. stats.totalFires .. " | Invokes: " .. stats.totalInvokes .. " | HTTP: " .. stats.totalHttpRequests .. " | Remotes: " .. uniqueCount
    end
    if uiElements.statusLabel then
        uiElements.statusLabel.Text = monitoring and "ACTIVE" or "PAUSED"
        uiElements.statusLabel.TextColor3 = monitoring and Color3.new(0.2, 0.8, 0.2) or Color3.new(0.8, 0.8, 0.2)
    end
end

createContextMenu = function(parent, remotePath, remoteArgs, remoteType)

    local existingMenu = gui:FindFirstChild("ContextMenu")
    if existingMenu then
        existingMenu:Destroy()
    end
    
    local contextMenu = Instance.new("Frame")
    contextMenu.Name = "ContextMenu"
    contextMenu.Size = UDim2.new(0, 140, 0, 118)
    contextMenu.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    contextMenu.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
    contextMenu.BorderSizePixel = 1
    contextMenu.ZIndex = 15
    contextMenu.Parent = gui
    
    local mouse = Players.LocalPlayer:GetMouse()
    contextMenu.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
    
    local function createMenuButton(text, yPos, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, -4, 0, 20)
        button.Position = UDim2.new(0, 2, 0, yPos)
        button.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
        button.BorderColor3 = Color3.new(0.25, 0.25, 0.25)
        button.BorderSizePixel = 1
        button.Text = text
        button.TextColor3 = Color3.new(0.8, 0.8, 0.8)
        button.TextSize = 11
        button.Font = Enum.Font.SourceSans
        button.ZIndex = 16
        button.Parent = contextMenu
        
        button.MouseEnter:Connect(function()
            button.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
        end)
        
        button.MouseLeave:Connect(function()
            button.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
        end)
        
        button.MouseButton1Click:Connect(function()
            callback()
            contextMenu:Destroy()
        end)
        
        return button
    end
    

    createMenuButton("> Copy Path", 2, function()
        copyToClipboard(remotePath)
    end)
    

    createMenuButton("> Copy Code", 25, function()
        local code = ""
        local argsCode = ""
        
        if remoteArgs and remoteArgs ~= "(no arguments)" and remoteArgs ~= "" then
            argsCode = remoteArgs
        end
        
        if remoteType == "FireServer" then
            code = "game." .. remotePath .. ":FireServer(" .. argsCode .. ")"
        elseif remoteType == "InvokeServer" then
            code = "game." .. remotePath .. ":InvokeServer(" .. argsCode .. ")"
        else
            if remotePath:find("RemoteEvent") then
                code = "game." .. remotePath .. ":FireServer(" .. argsCode .. ")"
            else
                code = "game." .. remotePath .. ":InvokeServer(" .. argsCode .. ")"
            end
        end
        copyToClipboard(code)
    end)
    

    createMenuButton("> Copy Full Path", 48, function()
        copyToClipboard("game." .. remotePath)
    end)
    

    createMenuButton("> Run Remote", 71, function()
        pcall(function()
            local remote = game
            local pathParts = {}
            for part in remotePath:gmatch("[^%.]+") do
                table.insert(pathParts, part)
            end
            
            for _, part in ipairs(pathParts) do
                remote = remote[part]
            end
            
            if remote then
                local parsedArgs = parseArguments(remoteArgs)
                
                if remote.ClassName == "RemoteEvent" then
                    if #parsedArgs > 0 then
                        remote:FireServer(unpack(parsedArgs))
                        addLog("> Fired remote with args: " .. remotePath, Color3.new(0.2, 0.8, 0.2))
                    else
                        remote:FireServer()
                        addLog("> Fired remote: " .. remotePath, Color3.new(0.2, 0.8, 0.2))
                    end
                elseif remote.ClassName == "RemoteFunction" then
                    local success, result = pcall(function()
                        if #parsedArgs > 0 then
                            return remote:InvokeServer(unpack(parsedArgs))
                        else
                            return remote:InvokeServer()
                        end
                    end)
                    if success then
                        addLog("> Invoked remote: " .. remotePath .. " | Result: " .. tostring(result), Color3.new(0.2, 0.8, 0.2))
                    else
                        addLog("> Failed to invoke: " .. remotePath .. " | Error: " .. tostring(result), Color3.new(1, 0.5, 0.5))
                    end
                else
                    addLog("> Invalid remote type: " .. remotePath, Color3.new(1, 0.5, 0.5))
                end
            else
                addLog("> Remote not found: " .. remotePath, Color3.new(1, 0.5, 0.5))
            end
        end)
    end)
    

    if remoteArgs and remoteArgs ~= "(no arguments)" and remoteArgs ~= "" then
        createMenuButton("> Copy Args", 94, function()
            copyToClipboard(remoteArgs)
        end)
    end
    

    local contextDragging, contextDragStart, contextStartPos = false, nil, nil
    
    contextMenu.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not buttonInteraction then
            contextDragging = true
            contextDragStart = input.Position
            contextStartPos = contextMenu.Position
        end
    end)
    
    contextMenu.InputChanged:Connect(function(input)
        if contextDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - contextDragStart
            contextMenu.Position = UDim2.new(contextStartPos.X.Scale, contextStartPos.X.Offset + delta.X, contextStartPos.Y.Scale, contextStartPos.Y.Offset + delta.Y)
        end
    end)
    
    contextMenu.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            contextDragging = false
        end
    end)
    

    local connection
    connection = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and not contextDragging then
            local mousePos = UserInputService:GetMouseLocation()
            local menuPos = contextMenu.AbsolutePosition
            local menuSize = contextMenu.AbsoluteSize
            

            if mousePos.X < menuPos.X or mousePos.X > menuPos.X + menuSize.X or
               mousePos.Y < menuPos.Y or mousePos.Y > menuPos.Y + menuSize.Y then
                contextMenu:Destroy()
                connection:Disconnect()
            end
        end
    end)
    

    game:GetService("Debris"):AddItem(contextMenu, 10)
end

connectButtons = function()
    if not uiElements or not uiElements.buttons then 
        return 
    end
    
    local buttons = uiElements.buttons
    
    buttons.copyPathBtn.MouseButton1Click:Connect(function()
        pcall(function()
            if selectedRemote then
                copyToClipboard(selectedRemote.path)
            else
                addLog("No remote selected!", Color3.new(1, 0.8, 0.2))
            end
        end)
    end)
    
    buttons.copyArgsBtn.MouseButton1Click:Connect(function()
        pcall(function()
            if selectedRemote then
                copyToClipboard(selectedRemote.args or "(no arguments)")
            else
                addLog("No remote selected!", Color3.new(1, 0.8, 0.2))
            end
        end)
    end)
    
    buttons.copyCodeBtn.MouseButton1Click:Connect(function()
        pcall(function()
            if selectedRemote then
                local argsCode = ""
                if selectedRemote.args and selectedRemote.args ~= "(no arguments)" and selectedRemote.args ~= "" then
                    argsCode = selectedRemote.args
                end
                local code = selectedRemote.type == "FireServer" and "game." .. selectedRemote.path .. ":FireServer(" .. argsCode .. ")" or "game." .. selectedRemote.path .. ":InvokeServer(" .. argsCode .. ")"
                copyToClipboard(code)
            else
                addLog("No remote selected!", Color3.new(1, 0.8, 0.2))
            end
        end)
    end)
    
    buttons.runBtn.MouseButton1Click:Connect(function()
        pcall(function()
            if selectedRemote then
                local remote = game
                local pathParts = {}
                for part in selectedRemote.path:gmatch("[^%.]+") do
                    table.insert(pathParts, part)
                end
                
                for _, part in ipairs(pathParts) do
                    remote = remote[part]
                end
                
                if remote then
                    local parsedArgs = parseArguments(selectedRemote.args)
                    
                    if remote.ClassName == "RemoteEvent" then
                        if #parsedArgs > 0 then
                            remote:FireServer(unpack(parsedArgs))
                            addLog("> Fired remote with args: " .. selectedRemote.path, Color3.new(0.2, 0.8, 0.2))
                        else
                            remote:FireServer()
                            addLog("> Fired remote: " .. selectedRemote.path, Color3.new(0.2, 0.8, 0.2))
                        end
                    elseif remote.ClassName == "RemoteFunction" then
                        local success, result = pcall(function()
                            if #parsedArgs > 0 then
                                return remote:InvokeServer(unpack(parsedArgs))
                            else
                                return remote:InvokeServer()
                            end
                        end)
                        if success then
                            addLog("> Invoked remote: " .. selectedRemote.path .. " | Result: " .. tostring(result), Color3.new(0.2, 0.8, 0.2))
                        else
                            addLog("> Failed to invoke: " .. selectedRemote.path .. " | Error: " .. tostring(result), Color3.new(1, 0.5, 0.5))
                        end
                    else
                        addLog("> Invalid remote type: " .. selectedRemote.path, Color3.new(1, 0.5, 0.5))
                    end
                else
                    addLog("> Remote not found: " .. selectedRemote.path, Color3.new(1, 0.5, 0.5))
                end
            else
                addLog("No remote selected!", Color3.new(1, 0.8, 0.2))
            end
        end)
    end)
    
    buttons.clearBtn.MouseButton1Click:Connect(function()
        pcall(function()
            _G.RemoteSpyClear()
        end)
    end)
    
    buttons.exportBtn.MouseButton1Click:Connect(function()
        pcall(function()
            local exportString = "-- Remote Spy Export Data\n-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\nStatistics:\n- Total Fires: " .. stats.totalFires .. "\n- Total Invokes: " .. stats.totalInvokes .. "\n- Session Duration: " .. math.floor(tick() - stats.sessionStart) .. " seconds\n\nUnique Remotes:\n"
            
            for remotePath, count in pairs(stats.uniqueRemotes) do
                exportString = exportString .. "- " .. remotePath .. " (" .. count .. " calls)\n"
            end
            
            copyToClipboard(exportString)
            addLog("Export data copied to clipboard!", Color3.new(0.2, 0.8, 0.2))
        end)
    end)
    
    buttons.settingsBtn.MouseButton1Click:Connect(function()
        pcall(function()
            if not settingsFrame then
                createSettingsFrame()
            end
            settingsFrame.Visible = not settingsFrame.Visible
        end)
    end)
    
    buttons.toggleBtn.MouseButton1Click:Connect(function()
        pcall(function()
            monitoring = not monitoring
            buttons.toggleBtn.Text = monitoring and "Stop Monitoring" or "Start Monitoring"
            buttons.toggleBtn.BackgroundColor3 = monitoring and Color3.new(0.15, 0.15, 0.15) or Color3.new(0.2, 0.15, 0.15)
            updateStats()
            addLog("Monitoring: " .. (monitoring and "STARTED" or "STOPPED"), Color3.new(1, 1, 0))
        end)
    end)
    
    buttons.blockBtn.MouseButton1Click:Connect(function()
        pcall(function()
            if selectedRemote then
                local remotePath = selectedRemote.path
                if blockedRemotes[remotePath] then
                    blockedRemotes[remotePath] = nil
                    buttons.blockBtn.Text = "Block Remote"
                    buttons.blockBtn.BackgroundColor3 = Color3.new(0.2, 0.1, 0.1)
                    addLog("> Remote unblocked: " .. remotePath, Color3.new(0.2, 0.8, 0.2))
                else
                    blockedRemotes[remotePath] = true
                    buttons.blockBtn.Text = "Unblock Remote"
                    buttons.blockBtn.BackgroundColor3 = Color3.new(0.1, 0.2, 0.1)
                    addLog("> Remote blocked: " .. remotePath, Color3.new(1, 0.8, 0.2))
                end
            else
                addLog("No remote selected!", Color3.new(1, 0.8, 0.2))
            end
        end)
    end)
    
    if uiElements.searchBox then
        uiElements.searchBox.Changed:Connect(function(property)
            pcall(function()
                if property == "Text" then
                    local searchText = uiElements.searchBox.Text:lower()
                    for _, log in ipairs(logs) do
                        if log then
                            local textLabel = log:FindFirstChild("TextLabel")
                            if textLabel then
                                log.Visible = searchText == "" or textLabel.Text:lower():find(searchText) ~= nil
                            end
                        end
                    end
                end
            end)
        end)
    end
end

addGroupedLog = function(remotePath, remoteType, remoteArgs, timestamp)
    if not gui or not logFrame then return end
    

    if not remoteGroups[remotePath] then
        remoteGroups[remotePath] = {
            count = 0,
            type = remoteType,
            lastArgs = remoteArgs,
            lastTimestamp = timestamp,
            logContainer = nil,
            expanded = false,
            recentCalls = {},
            expandedLogs = {}
        }
        

        local yPos = 0
        for _, log in ipairs(logs) do
            yPos = yPos + log.Size.Y.Offset
        end
        

        local groupContainer = Instance.new("Frame")
        groupContainer.Size = UDim2.new(1, -10, 0, 30)
        groupContainer.Position = UDim2.new(0, 5, 0, yPos)
        groupContainer.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
        groupContainer.BorderColor3 = Color3.new(0.2, 0.2, 0.2)
        groupContainer.BorderSizePixel = 1
        groupContainer.Parent = logFrame
        

        local arrow = Instance.new("TextLabel")
        arrow.Size = UDim2.new(0, 15, 1, 0)
        arrow.Position = UDim2.new(0, 5, 0, 0)
        arrow.BackgroundTransparency = 1
        arrow.Text = ">"
        arrow.TextColor3 = Color3.new(0.8, 0.8, 0.8)
        arrow.TextSize = 12
        arrow.Font = Enum.Font.SourceSans
        arrow.TextXAlignment = Enum.TextXAlignment.Center
        arrow.Parent = groupContainer
        

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -80, 1, -5)
        nameLabel.Position = UDim2.new(0, 20, 0, 2)
        nameLabel.BackgroundTransparency = 1
        local displayText = (remoteType == "FireServer" and "> FIRE: " or "> INVOKE: ") .. remotePath
        nameLabel.Text = displayText
        nameLabel.TextColor3 = remoteType == "FireServer" and Color3.new(1, 0.5, 0.5) or Color3.new(1, 1, 0.5)
        nameLabel.TextSize = 10
        nameLabel.Font = Enum.Font.SourceSans
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextYAlignment = Enum.TextYAlignment.Top
        nameLabel.TextWrapped = true
        nameLabel.Parent = groupContainer
        
        -- Count label
        local countLabel = Instance.new("TextLabel")
        countLabel.Size = UDim2.new(0, 60, 1, 0)
        countLabel.Position = UDim2.new(1, -65, 0, 0)
        countLabel.BackgroundTransparency = 1
        countLabel.Text = "(1)"
        countLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
        countLabel.TextSize = 11
        countLabel.Font = Enum.Font.SourceSans
        countLabel.TextXAlignment = Enum.TextXAlignment.Right
        countLabel.Parent = groupContainer
        
        remoteGroups[remotePath].logContainer = groupContainer
        remoteGroups[remotePath].arrow = arrow
        remoteGroups[remotePath].countLabel = countLabel
        remoteGroups[remotePath].nameLabel = nameLabel
        
        -- Add hover effects
        groupContainer.MouseEnter:Connect(function()
            groupContainer.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
        end)
        
        groupContainer.MouseLeave:Connect(function()
            if selectedRemote and selectedRemote.logContainer == groupContainer then
                groupContainer.BackgroundColor3 = Color3.new(0.2, 0.3, 0.4)
            else
                groupContainer.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
            end
        end)
        
        -- Click to expand/collapse and right-click for context menu
        groupContainer.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                remoteGroups[remotePath].expanded = not remoteGroups[remotePath].expanded
                arrow.Text = remoteGroups[remotePath].expanded and "v" or ">"
                
                -- Show/hide expanded logs
                if remoteGroups[remotePath].expanded then
                    -- Show individual calls
                    for i, expandedLog in ipairs(remoteGroups[remotePath].expandedLogs) do
                        expandedLog.Visible = true
                    end
                else
                    -- Hide individual calls
                    for i, expandedLog in ipairs(remoteGroups[remotePath].expandedLogs) do
                        expandedLog.Visible = false
                    end
                end
                
                -- Recalculate positions for all logs
                local yPos = 0
                for _, log in ipairs(logs) do
                    if log.Visible then
                        log.Position = UDim2.new(0, 5, 0, yPos)
                        yPos = yPos + log.Size.Y.Offset
                    end
                end
                
                -- Update canvas size
                local totalHeight = 0
                for _, log in ipairs(logs) do
                    if log.Visible then
                        totalHeight = totalHeight + log.Size.Y.Offset
                    end
                end
                logFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
                
                -- Update selection
                if selectedRemote and selectedRemote.logContainer then
                    selectedRemote.logContainer.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
                end
                
                selectedRemote = {
                    path = remotePath,
                    args = remoteArgs,
                    type = remoteType,
                    logContainer = groupContainer
                }
                
                groupContainer.BackgroundColor3 = Color3.new(0.2, 0.3, 0.4)
                
                if uiElements.selectedInfo then
                    local displayPath = remotePath:len() > 30 and remotePath:sub(1, 30) .. "..." or remotePath
                    local displayArgs = (remoteArgs and remoteArgs:len() > 50) and remoteArgs:sub(1, 50) .. "..." or (remoteArgs or "(no arguments)")
                    uiElements.selectedInfo.Text = "Path: " .. displayPath .. "\n\nArguments: " .. displayArgs .. "\n\nCalls: " .. remoteGroups[remotePath].count
                    uiElements.selectedInfo.TextColor3 = Color3.new(0.9, 0.9, 0.9)
                end
                
                -- Update block button text
                if uiElements.buttons and uiElements.buttons.blockBtn then
                    if blockedRemotes[remotePath] then
                        uiElements.buttons.blockBtn.Text = "Unblock Remote"
                        uiElements.buttons.blockBtn.BackgroundColor3 = Color3.new(0.1, 0.2, 0.1)
                    else
                        uiElements.buttons.blockBtn.Text = "Block Remote"
                        uiElements.buttons.blockBtn.BackgroundColor3 = Color3.new(0.2, 0.1, 0.1)
                    end
                end
            elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
                -- Right-click for context menu
                createContextMenu(groupContainer, remotePath, remoteArgs, remoteType)
            end
        end)
        
        table.insert(logs, groupContainer)
    end
    
    -- Always add the individual call to recent calls (limit to last 10)
    local callData = {
        timestamp = timestamp,
        args = remoteArgs,
        type = remoteType
    }
    table.insert(remoteGroups[remotePath].recentCalls, 1, callData)
    if #remoteGroups[remotePath].recentCalls > 10 then
        table.remove(remoteGroups[remotePath].recentCalls)
    end
    
    -- Update existing group
    remoteGroups[remotePath].count = remoteGroups[remotePath].count + 1
    remoteGroups[remotePath].lastArgs = remoteArgs
    remoteGroups[remotePath].lastTimestamp = timestamp
    if remoteGroups[remotePath].countLabel then
        remoteGroups[remotePath].countLabel.Text = "(" .. remoteGroups[remotePath].count .. ")"
    end
    
    -- Create individual log entry for this call
    local individualLog = Instance.new("Frame")
    individualLog.Size = UDim2.new(1, -20, 0, 20)
    individualLog.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    individualLog.BorderColor3 = Color3.new(0.15, 0.15, 0.15)
    individualLog.BorderSizePixel = 1
    individualLog.Visible = remoteGroups[remotePath].expanded
    individualLog.Parent = logFrame
    
    local indentLabel = Instance.new("TextLabel")
    indentLabel.Size = UDim2.new(0, 30, 1, 0)
    indentLabel.Position = UDim2.new(0, 10, 0, 0)
    indentLabel.BackgroundTransparency = 1
    indentLabel.Text = "  >"
    indentLabel.TextColor3 = Color3.new(0.5, 0.5, 0.5)
    indentLabel.TextSize = 10
    indentLabel.Font = Enum.Font.SourceSans
    indentLabel.TextXAlignment = Enum.TextXAlignment.Left
    indentLabel.Parent = individualLog
    
    local timeLabel = Instance.new("TextLabel")
    timeLabel.Size = UDim2.new(0, 60, 1, 0)
    timeLabel.Position = UDim2.new(0, 35, 0, 0)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Text = timestamp
    timeLabel.TextColor3 = Color3.new(0.6, 0.6, 0.6)
    timeLabel.TextSize = 10
    timeLabel.Font = Enum.Font.SourceSans
    timeLabel.TextXAlignment = Enum.TextXAlignment.Left
    timeLabel.Parent = individualLog
    
    local argsLabel = Instance.new("TextLabel")
    argsLabel.Size = UDim2.new(1, -100, 1, 0)
    argsLabel.Position = UDim2.new(0, 100, 0, 0)
    argsLabel.BackgroundTransparency = 1
    local displayArgs = remoteArgs and remoteArgs:len() > 40 and remoteArgs:sub(1, 40) .. "..." or (remoteArgs or "(no args)")
    argsLabel.Text = displayArgs
    argsLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    argsLabel.TextSize = 10
    argsLabel.Font = Enum.Font.SourceSans
    argsLabel.TextXAlignment = Enum.TextXAlignment.Left
    argsLabel.TextTruncate = Enum.TextTruncate.AtEnd
    argsLabel.Parent = individualLog
    
    -- Add hover and click functionality
    individualLog.MouseEnter:Connect(function()
        individualLog.BackgroundColor3 = Color3.new(0.12, 0.12, 0.12)
    end)
    
    individualLog.MouseLeave:Connect(function()
        individualLog.BackgroundColor3 = Color3.new(0.08, 0.08, 0.08)
    end)
    
    individualLog.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            copyToClipboard(remoteArgs or "(no arguments)")
            addLog("> Copied arguments from individual call", Color3.new(0.5, 1, 0.5))
        end
    end)
    
    -- Add to expanded logs list
    table.insert(remoteGroups[remotePath].expandedLogs, individualLog)
    
    -- Limit expanded logs to last 10
    if #remoteGroups[remotePath].expandedLogs > 10 then
        local oldLog = remoteGroups[remotePath].expandedLogs[1]
        oldLog:Destroy()
        table.remove(remoteGroups[remotePath].expandedLogs, 1)
    end
    
    -- Insert individual log right after its group container
    local groupIndex = -1
    for i, log in ipairs(logs) do
        if log == remoteGroups[remotePath].logContainer then
            groupIndex = i
            break
        end
    end
    
    if groupIndex > 0 then
        -- Find where to insert (after other expanded logs of this group)
        local insertIndex = groupIndex + 1
        for i = groupIndex + 1, #logs do
            if logs[i].Parent == logFrame and logs[i].Size.Y.Offset == 20 then
                -- This is an individual log, check if it belongs to our group
                local belongsToGroup = false
                for _, expandedLog in ipairs(remoteGroups[remotePath].expandedLogs) do
                    if expandedLog == logs[i] then
                        belongsToGroup = true
                        break
                    end
                end
                if belongsToGroup then
                    insertIndex = i + 1
                else
                    break
                end
            else
                break
            end
        end
        table.insert(logs, insertIndex, individualLog)
    else
        table.insert(logs, individualLog)
    end
    
    -- Update positions for all logs
    local yPos = 0
    for _, log in ipairs(logs) do
        if log.Visible then
            log.Position = UDim2.new(0, 5, 0, yPos)
            yPos = yPos + log.Size.Y.Offset
        end
    end
    
    -- Update canvas size
    local totalHeight = 0
    for _, log in ipairs(logs) do
        if log.Visible then
            totalHeight = totalHeight + log.Size.Y.Offset
        end
    end
    logFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
    logFrame.CanvasPosition = Vector2.new(0, logFrame.CanvasSize.Y.Offset)
end

addLog = function(text, color, remotePath, remoteArgs, logType)
    if not gui or not logFrame then return end
    
    -- If this is a remote log and we have a path, use grouped logging
    if remotePath and logType ~= "code" then
        local remoteType = text:match("FIRE:") and "FireServer" or "InvokeServer"
        local timestamp = text:match("%[(.-)%]") or os.date("%H:%M:%S")
        addGroupedLog(remotePath, remoteType, remoteArgs, timestamp)
        return
    end
    
    -- Calculate position based on existing logs
    local yPos = 0
    for _, log in ipairs(logs) do
        yPos = yPos + log.Size.Y.Offset
    end
    
    local logContainer = Instance.new("Frame")
    logContainer.Size = UDim2.new(1, -10, 0, 20)
    logContainer.Position = UDim2.new(0, 5, 0, yPos)
    logContainer.BackgroundTransparency = 1
    logContainer.Parent = logFrame
    
    local logEntry = Instance.new("TextLabel")
    logEntry.Size = UDim2.new(1, 0, 1, 0)
    logEntry.Position = UDim2.new(0, 0, 0, 0)
    logEntry.BackgroundTransparency = 1
    logEntry.Text = text
    logEntry.TextColor3 = color or Color3.new(1, 1, 1)
    logEntry.TextScaled = false
    logEntry.TextSize = 12
    logEntry.Font = Enum.Font.SourceSans
    logEntry.TextXAlignment = Enum.TextXAlignment.Left
    logEntry.Parent = logContainer
    
    -- Special handling for code lines
    if logType == "code" then
        -- Add click indicator
        local clickIndicator = Instance.new("TextLabel")
        clickIndicator.Size = UDim2.new(0, 60, 1, 0)
        clickIndicator.Position = UDim2.new(1, -65, 0, 0)
        clickIndicator.BackgroundTransparency = 1
        clickIndicator.Text = "(click)"
        clickIndicator.TextColor3 = Color3.new(0.6, 0.6, 0.6)
        clickIndicator.TextSize = 10
        clickIndicator.Font = Enum.Font.SourceSans
        clickIndicator.TextXAlignment = Enum.TextXAlignment.Right
        clickIndicator.Parent = logContainer
        
        logContainer.MouseEnter:Connect(function()
            logEntry.BackgroundTransparency = 0.9
            logEntry.BackgroundColor3 = Color3.new(0.2, 0.4, 0.6)
            clickIndicator.TextColor3 = Color3.new(1, 1, 1)
        end)
        
        logContainer.MouseLeave:Connect(function()
            logEntry.BackgroundTransparency = 1
            clickIndicator.TextColor3 = Color3.new(0.6, 0.6, 0.6)
        end)
        
        logContainer.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                copyToClipboard(remoteArgs) -- remoteArgs contains the executable code for code lines
                addLog("> Code copied: " .. (remoteArgs:len() > 30 and remoteArgs:sub(1, 30) .. "..." or remoteArgs), Color3.new(0.5, 1, 0.5))
            end
        end)
    elseif remotePath then
        logContainer.MouseEnter:Connect(function()
            logEntry.BackgroundTransparency = 0.9
            logEntry.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
        end)
        
        logContainer.MouseLeave:Connect(function()
            if selectedRemote and selectedRemote.logContainer == logContainer then
                logEntry.BackgroundTransparency = 0.8
                logEntry.BackgroundColor3 = Color3.new(0.3, 0.5, 0.8)
            else
                logEntry.BackgroundTransparency = 1
            end
        end)
        
        logContainer.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                if selectedRemote and selectedRemote.logContainer then
                    local prevEntry = selectedRemote.logContainer:FindFirstChild("TextLabel")
                    if prevEntry then
                        prevEntry.BackgroundTransparency = 1
                    end
                end
                
                selectedRemote = {
                    path = remotePath,
                    args = remoteArgs,
                    type = text:match("FIRE:") and "FireServer" or "InvokeServer",
                    logContainer = logContainer
                }
                
                logEntry.BackgroundTransparency = 0.8
                logEntry.BackgroundColor3 = Color3.new(0.3, 0.5, 0.8)
                
                if uiElements.selectedInfo then
                    local displayPath = remotePath:len() > 30 and remotePath:sub(1, 30) .. "..." or remotePath
                    local displayArgs = (remoteArgs and remoteArgs:len() > 50) and remoteArgs:sub(1, 50) .. "..." or (remoteArgs or "(no arguments)")
                    uiElements.selectedInfo.Text = "Path: " .. displayPath .. "\n\nArguments: " .. displayArgs
                    uiElements.selectedInfo.TextColor3 = Color3.new(0.9, 0.9, 0.9)
                end
                
            elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
                local remoteType = text:match("FIRE:") and "FireServer" or "InvokeServer"
                createContextMenu(logContainer, remotePath, remoteArgs, remoteType)
            end
        end)
    end
    
    table.insert(logs, logContainer)
    
    if #logs > maxLogs then
        logs[1]:Destroy()
        table.remove(logs, 1)
        
        local yPos = 0
        for i, log in ipairs(logs) do
            local height = log.Size.Y.Offset
            log.Position = UDim2.new(0, 5, 0, yPos)
            yPos = yPos + height
        end
    end
    
    -- Calculate total height
    local totalHeight = 0
    for _, log in ipairs(logs) do
        totalHeight = totalHeight + log.Size.Y.Offset
    end
    
    logFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
    logFrame.CanvasPosition = Vector2.new(0, logFrame.CanvasSize.Y.Offset)
end

local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall

setreadonly(mt, false)

mt.__namecall = function(self, ...)
    local method = getnamecallmethod()
    
    if enabled and monitoring and typeof(self) == "Instance" then
        if method == "FireServer" and self.ClassName == "RemoteEvent" then
            local path = getPath(self)
            
            if blockedRemotes[path] then
                addLog("> BLOCKED FIRE: " .. path, Color3.new(1, 0.3, 0.3))
                return
            end
            
            local timestamp = os.date("%H:%M:%S")
            local args = {...}
            
            local formattedArgs = ""
            if #args > 0 then
                local argList = {}
                for i = 1, #args do
                    table.insert(argList, "[" .. i .. "] " .. formatValue(args[i]))
                end
                formattedArgs = table.concat(argList, ", ")
            else
                formattedArgs = "(no arguments)"
            end
            
            addLog("[" .. timestamp .. "] > FIRE: " .. path, Color3.new(1, 0.5, 0.5), path, formattedArgs)
            
            stats.totalFires = stats.totalFires + 1
            stats.uniqueRemotes[path] = (stats.uniqueRemotes[path] or 0) + 1
            updateStats()
        end
        
        if method == "InvokeServer" and self.ClassName == "RemoteFunction" then
            local path = getPath(self)
            
            if blockedRemotes[path] then
                addLog("> BLOCKED INVOKE: " .. path, Color3.new(1, 0.3, 0.3))
                return
            end
            
            local timestamp = os.date("%H:%M:%S")
            local args = {...}
            
            local formattedArgs = ""
            if #args > 0 then
                local argList = {}
                for i = 1, #args do
                    table.insert(argList, "[" .. i .. "] " .. formatValue(args[i]))
                end
                formattedArgs = table.concat(argList, ", ")
            else
                formattedArgs = "(no arguments)"
            end
            
            addLog("[" .. timestamp .. "] > INVOKE: " .. path, Color3.new(1, 1, 0.5), path, formattedArgs)
            
            stats.totalInvokes = stats.totalInvokes + 1
            stats.uniqueRemotes[path] = (stats.uniqueRemotes[path] or 0) + 1
            updateStats()
        end
    end
    
    return oldNamecall(self, ...)
end

setreadonly(mt, true)

local HttpGet
if game.HttpGet then
    HttpGet = hookfunction(game.HttpGet, function(self, url, ...)
        if enabled and monitoring then
            pcall(function()
                addHttpLog("HTTP GET", url, nil, nil, nil, nil)
                stats.totalHttpRequests = stats.totalHttpRequests + 1
            end)
        end
        return HttpGet(self, url, ...)
    end)
end

local HttpPost
if game.HttpPost then
    HttpPost = hookfunction(game.HttpPost, function(self, url, ...)
        if enabled and monitoring then
            pcall(function()
                addHttpLog("HTTP POST", url, nil, nil, nil, nil)
                stats.totalHttpRequests = stats.totalHttpRequests + 1
            end)
        end
        return HttpPost(self, url, ...)
    end)
end

local RequestLog
if syn and syn.request then
    RequestLog = hookfunction(syn.request, function(dat)
        if enabled and monitoring then
            pcall(function()
                addHttpLog(dat.Method or "REQUEST", dat.Url, dat.Headers, dat.Body, nil, nil)
                stats.totalHttpRequests = stats.totalHttpRequests + 1
            end)
        end
        local response = RequestLog(dat)
        if enabled and monitoring and response then
            pcall(function()
                addHttpLog(dat.Method or "REQUEST", dat.Url, dat.Headers, dat.Body, response.Body, response.StatusCode)
            end)
        end
        return response
    end)
elseif request then
    RequestLog = hookfunction(request, function(dat)
        if enabled and monitoring then
            pcall(function()
                addHttpLog(dat.Method or "REQUEST", dat.Url, dat.Headers, dat.Body, nil, nil)
                stats.totalHttpRequests = stats.totalHttpRequests + 1
            end)
        end
        local response = RequestLog(dat)
        if enabled and monitoring and response then
            pcall(function()
                addHttpLog(dat.Method or "REQUEST", dat.Url, dat.Headers, dat.Body, response.Body, response.StatusCode)
            end)
        end
        return response
    end)
elseif http_request then
    RequestLog = hookfunction(http_request, function(dat)
        if enabled and monitoring then
            pcall(function()
                addHttpLog(dat.Method or "REQUEST", dat.Url, dat.Headers, dat.Body, nil, nil)
                stats.totalHttpRequests = stats.totalHttpRequests + 1
            end)
        end
        local response = RequestLog(dat)
        if enabled and monitoring and response then
            pcall(function()
                addHttpLog(dat.Method or "REQUEST", dat.Url, dat.Headers, dat.Body, response.Body, response.StatusCode)
            end)
        end
        return response
    end)
end



uiElements = createGUI()
createSettingsFrame()
createScriptViewer()

wait()

connectButtons()

addLog("> Remote Spy Active!", Color3.new(0.5, 1, 0.5))
addLog("> Monitoring RemoteEvent:FireServer", Color3.new(1, 1, 1))
addLog("> Monitoring RemoteFunction:InvokeServer", Color3.new(1, 1, 1))
addLog("=" .. string.rep("=", 30), Color3.new(0.5, 0.5, 0.5))

_G.RemoteSpyToggle = function()
    enabled = not enabled
    addLog("Remote Spy: " .. (enabled and "ENABLED" or "DISABLED"), Color3.new(1, 1, 0))
end

_G.RemoteSpyMonitor = function()
    monitoring = not monitoring
    if uiElements.buttons and uiElements.buttons.toggleBtn then
        uiElements.buttons.toggleBtn.Text = monitoring and "Stop Monitoring" or "Start Monitoring"
        uiElements.buttons.toggleBtn.BackgroundColor3 = monitoring and Color3.new(0.15, 0.15, 0.15) or Color3.new(0.2, 0.15, 0.15)
    end
    updateStats()
    addLog("Monitoring: " .. (monitoring and "STARTED" or "STOPPED"), Color3.new(1, 1, 0))
end

_G.RemoteSpyArgs = function()
    showArgs = not showArgs
    addLog("Show Arguments: " .. (showArgs and "ON" or "OFF"), Color3.new(1, 1, 0))
end

_G.RemoteSpyClear = function()
    for _, log in ipairs(logs) do
        log:Destroy()
    end
    for _, log in ipairs(httpLogs) do
        log:Destroy()
    end
    for _, log in ipairs(decompilerLogs) do
        log:Destroy()
    end
    logs = {}
    httpLogs = {}
    decompilerLogs = {}
    remoteGroups = {}
    expandedGroups = {}
    selectedRemote = nil
    logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    httpLogFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    decompilerFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    if uiElements.selectedInfo then
        uiElements.selectedInfo.Text = "Click a remote to select"
        uiElements.selectedInfo.TextColor3 = Color3.new(0.6, 0.6, 0.6)
    end
    addLog("> All logs cleared!", Color3.new(0.5, 1, 0.5))
end

_G.RemoteSpyClose = function()
    if gui then
        gui:Destroy()
        gui = nil
        logs = {}
    end
end

_G.TestHttpRequest = function()
    if syn and syn.request then
        pcall(function()
            syn.request({
                Url = "https://httpbin.org/get",
                Method = "GET"
            })
        end)
        addLog("> Test HTTP request sent (syn.request)", Color3.new(0.5, 1, 0.5))
    elseif request then
        pcall(function()
            request({
                Url = "https://httpbin.org/get",
                Method = "GET"
            })
        end)
        addLog("> Test HTTP request sent (request)", Color3.new(0.5, 1, 0.5))
    elseif http_request then
        pcall(function()
            http_request({
                Url = "https://httpbin.org/get",
                Method = "GET"
            })
        end)
        addLog("> Test HTTP request sent (http_request)", Color3.new(0.5, 1, 0.5))
    else
        addLog("> No HTTP request function available", Color3.new(1, 0.8, 0.2))
    end
end

_G.ScanGameScripts = function()
    scanGameScripts()
end

_G.ViewScript = function(scriptInstance)
    if not scriptInstance or not scriptInstance:IsA("LuaSourceContainer") then
        addLog("> Invalid script instance provided", Color3.new(1, 0.5, 0.5))
        return
    end
    
    local scriptName = scriptInstance.Name
    local scriptPath = getPath(scriptInstance)
    local scriptType = scriptInstance.ClassName
    local source = nil
    
    pcall(function()
        if decompile then
            source = decompile(scriptInstance)
        elseif getsource then
            source = getsource(scriptInstance)
        elseif scriptInstance.Source then
            source = scriptInstance.Source
        end
    end)
    
    showScriptInViewer(scriptName, scriptPath, source, scriptType)
    addLog("> Opened script in viewer: " .. scriptName, Color3.new(0.5, 1, 0.5))
end

_G.GetCallingScript = function()
    local callingScript = getCallingScript()
    if callingScript then
        _G.ViewScript(callingScript)
        addLog("> Found and opened calling script: " .. callingScript.Name, Color3.new(0.5, 1, 0.5))
    else
        addLog("> Could not get calling script", Color3.new(1, 0.8, 0.2))
    end
end

print("> Remote Spy GUI loaded!")
print("> Use _G.RemoteSpyToggle() to enable/disable")
print("> Use _G.RemoteSpyMonitor() to start/stop monitoring")
print("> Use _G.RemoteSpyArgs() to show/hide arguments")
print("> Use _G.RemoteSpyClear() to clear logs")
print("> Use _G.RemoteSpyClose() to close GUI")
print("> Use _G.TestHttpRequest() to test HTTP monitoring")
print("> Use _G.ScanGameScripts() to scan and decompile scripts")
print("> Use _G.ViewScript(script) to view a specific script")
print("> Use _G.GetCallingScript() to get and view calling script")
