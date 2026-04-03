local window_manager = {}

-- Track which Safari window IDs are associated with which profiles
window_manager.profileWindows = {}

function window_manager:getSafariApp()
    local apps = hs.application.applicationsForBundleID("com.apple.Safari")
    if #apps > 0 then
        return apps[1]
    end
    return nil
end

function window_manager:getSafariWindows()
    local safari = self:getSafariApp()
    if not safari then
        return {}
    end
    
    local allWindows = safari:allWindows()
    
    local windows = {}
    local index = 1
    for _, win in ipairs(allWindows) do
        if win:isStandard() then
            local title = win:title() or "Untitled"
            local id = win:id() or tostring(index)
            table.insert(windows, {
                index = index,
                title = title,
                id = tostring(id),
                hsWindow = win
            })
            index = index + 1
        end
    end
    
    return windows
end

function window_manager:findWindowWithProfile(targetProfile, windows)
    local coreProfile = targetProfile:lower()
    
    -- Check tracked profile-windows first
    for winId, profile in pairs(self.profileWindows) do
        if profile:lower() == targetProfile:lower() then
            -- Check if this window still exists
            for _, win in ipairs(windows) do
                if win.id == winId then
                    return win.index
                end
            end
            -- Window no longer exists, remove from tracking
            self.profileWindows[winId] = nil
        end
    end
    
    -- Check if any window title contains the profile name
    for _, win in ipairs(windows) do
        local title = win.title:lower()
        
        if title:find(coreProfile, 1, true) then
            return win.index
        end
        
        if title:find(targetProfile:lower(), 1, true) then
            return win.index
        end
    end
    
    return nil
end

function window_manager:trackProfileWindow(winId, profileName)
    self.profileWindows[winId] = profileName
end

function window_manager:activateWindow(index)
    hs.printf("Activating window at index %d", index)
    local safari = self:getSafariApp()
    if not safari then
        return false
    end
    
    local allWindows = safari:allWindows()
    local targetWindow = nil
    local currentIndex = 0
    
    for _, win in ipairs(allWindows) do
        if win:isStandard() then
            currentIndex = currentIndex + 1
            if currentIndex == index then
                targetWindow = win
                break
            end
        end
    end
    
    if targetWindow then
        targetWindow:focus()
        safari:activate()
        return true
    end
    
    return false
end

function window_manager:getFrontmostWindowId()
    local safari = self:getSafariApp()
    if not safari then
        return nil
    end
    
    local win = safari:focusedWindow()
    if win then
        local id = win:id()
        return tostring(id)
    end
    return nil
end

function window_manager:createWindowWithProfile(profileName, menuName)
    -- Use menuName if provided, otherwise use profileName
    local searchName = menuName or profileName
    
    -- First ensure Safari is frontmost
    hs.application.launchOrFocus("Safari")
    hs.timer.usleep(500000) -- 0.5 second
    
    local script = string.format([[ 
        tell application "System Events"
            tell process "Safari"
                tell menu bar 1
                    tell menu bar item "File"
                        tell menu 1
                            try
                                set newWindowItem to menu item "New Window"
                                tell newWindowItem
                                    try
                                        set subMenu to menu 1
                                        set subMenuItems to name of every menu item of subMenu
                                        
                                        repeat with subItem in subMenuItems
                                            if subItem contains "%s" then
                                                click menu item subItem of subMenu
                                                return "created_with_profile"
                                            end if
                                        end repeat
                                        
                                        click newWindowItem
                                        return "created_default"
                                    on error
                                        click newWindowItem
                                        return "created_default"
                                    end try
                                end tell
                            on error
                                return "error"
                            end try
                        end tell
                    end tell
                end tell
            end tell
        end tell
    ]], searchName)
    
    local ok, result = hs.osascript.applescript(script)
    
    if ok and result and (result:find("created") or result:find("profile")) then
        -- Give Safari a moment to create the window
        hs.timer.usleep(1000000)
        -- Get the frontmost window ID and track it
        local winId = self:getFrontmostWindowId()
        if winId then
            self:trackProfileWindow(winId, profileName)
        end
        return true
    end
    
    return false
end

function window_manager:isSafariRunning()
    local apps = hs.application.applicationsForBundleID("com.apple.Safari")
    return #apps > 0
end

function window_manager:launchSafari()
    hs.application.launchOrFocus("Safari")
end

return window_manager
