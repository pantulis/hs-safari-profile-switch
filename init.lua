--- === SafariProfileSwitcher ===
---
--- Switch between Safari profiles using a hotkey+chooser interface.
--- Automatically detects profiles from Safari's SQLite database and
--- switches to existing windows or creates new ones as needed.
---
--- Configuration (set before calling start()):
---   spoon.SafariProfileSwitcher:configure({
---       hotkey = {mods = {"alt"}, key = "A"},
---       chooser = {rows = 8, width = 25},
---       pill = {height = 12, widthRatio = 2, cornerRadiusDivisor = 5},
---       showTabTitles = true,
---       sortByRecency = true,
---       showLastUsed = true,
---       showWindowStatus = true
---   })
---
--- Download: https://github.com/user/SafariProfileSwitcher
--- License: MIT

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "SafariProfileSwitcher"
obj.version = "1.1"
obj.author = "User"
obj.license = "MIT"
obj.homepage = ""

-- Configuration (user-customizable)
obj.config = {
    -- Hotkey to show the profile chooser
    hotkey = {
        mods = {"alt"},
        key = "A"
    },
    
    -- Chooser appearance
    chooser = {
        rows = 8,
        width = 25
    },
    
    -- Profile color pill appearance
    pill = {
        height = 12,           -- Height in pixels
        widthRatio = 2,        -- Width = height * widthRatio
        cornerRadiusDivisor = 5  -- Radius = height / divisor
    },
    
    -- Feature toggles
    showTabTitles = true,      -- Show current tab title in parentheses
    sortByRecency = true,      -- Sort profiles by last used time
    showLastUsed = true,       -- Show "Last used: X ago" in subtext
    showWindowStatus = true    -- Show "Window open" / "Will create new window"
}

-- State
obj.profiles = {}
obj.detectionMethod = nil
obj.safariWatcher = nil
obj.chooser = nil
obj.detector = nil
obj.windowManager = nil
obj.profileLastUsed = {}
obj.hotkey = nil

-- Allow users to override configuration
-- Usage: spoon.SafariProfileSwitcher:configure({hotkey = {mods = {"cmd", "alt"}, key = "S"}})
function obj:configure(userConfig)
    if userConfig then
        for key, value in pairs(userConfig) do
            if type(value) == "table" and type(self.config[key]) == "table" then
                -- Deep merge for nested tables
                for subKey, subValue in pairs(value) do
                    self.config[key][subKey] = subValue
                end
            else
                self.config[key] = value
            end
        end
    end
    return self
end

-- Load submodules
local function loadModule(name)
    local path = hs.spoons.resourcePath("lib/" .. name .. ".lua")
    local chunk, err = loadfile(path)
    if not chunk then
        hs.showError("Failed to load " .. name .. ": " .. (err or "unknown error"))
        return nil
    end
    return chunk()
end

function obj:init()
    self.detector = loadModule("detector")
    self.windowManager = loadModule("window_manager")
    
    self.chooser = hs.chooser.new(function(choice) 
        self:onProfileSelected(choice) 
    end)
    self.chooser:rows(self.config.chooser.rows)
    self.chooser:width(self.config.chooser.width)
    
    return self
end

function obj:start()
    -- Bind hotkey from config
    self.hotkey = hs.hotkey.bind(self.config.hotkey.mods, self.config.hotkey.key, function() 
        self:showChooser() 
    end)
    
    -- Watch Safari for restarts
    self.safariWatcher = hs.application.watcher.new(function(appName, eventType)
        if appName == "Safari" and eventType == hs.application.watcher.launched then
            hs.timer.doAfter(2, function() self:refreshProfiles() end)
        end
    end)
    self.safariWatcher:start()
    
    -- Initial load
    self:loadProfiles()
    
    return self
end

function obj:stop()
    if self.hotkey then self.hotkey:delete() end
    if self.safariWatcher then self.safariWatcher:stop() end
    return self
end

function obj:loadProfiles()
    -- Load profiles directly into memory (no file cache)
    self:refreshProfiles()
end

function obj:refreshProfiles()
    self.profiles, self.detectionMethod = self.detector:detectProfiles()
end

function obj:formatTimeAgo(timestamp)
    if not timestamp then return nil end
    
    local now = os.time()
    local diff = now - timestamp
    
    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        local mins = math.floor(diff / 60)
        return mins .. "m ago"
    elseif diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. "h ago"
    else
        local days = math.floor(diff / 86400)
        return days .. "d ago"
    end
end

function obj:sortProfilesByRecency()
    -- Separate profiles into used and unused
    local used = {}
    local unused = {}
    
    for _, profile in ipairs(self.profiles) do
        local lastUsed = self.profileLastUsed[profile.uuid]
        if lastUsed then
            table.insert(used, {profile = profile, lastUsed = lastUsed})
        else
            table.insert(unused, profile)
        end
    end
    
    -- Sort used profiles by recency (most recent first)
    table.sort(used, function(a, b)
        return a.lastUsed > b.lastUsed
    end)
    
    -- Sort unused profiles alphabetically
    table.sort(unused, function(a, b)
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    
    -- Combine: used first (by recency), then unused (alphabetically)
    local sorted = {}
    for _, item in ipairs(used) do
        table.insert(sorted, item.profile)
    end
    for _, profile in ipairs(unused) do
        table.insert(sorted, profile)
    end
    
    return sorted
end

function obj:showChooser()
    if #self.profiles == 0 then
        -- Try to refresh profiles one more time
        hs.alert.show("Refreshing Safari profiles...")
        self:refreshProfiles()

        -- If still empty after refresh
        if #self.profiles == 0 then
            if not self.detector:isSafariRunning() then
                hs.alert.show("No Safari profiles found. Opening Safari first...")
                self.windowManager:launchSafari()
                hs.timer.doAfter(3, function()
                    self:refreshProfiles()
                    self:showChooser()
                end)
            else
                hs.alert.show("No profiles found. Ensure Hammerspoon has Accessibility permissions.")
            end
            return
        end
    end
    
    -- Get current Safari windows to check which profiles have windows open
    local windows = self.windowManager:getSafariWindows()
    
    -- Separate profiles into active (has window) and inactive (no window)
    local activeProfiles = {}
    local inactiveProfiles = {}
    
    for _, profile in ipairs(self.profiles) do
        local winIndex = self.windowManager:findWindowWithProfile(profile.name, windows)
        local hasWindow = winIndex ~= nil
        local lastUsed = self.profileLastUsed[profile.uuid]
        local tabTitle = nil
        
        if hasWindow then
            -- Get the tab title from the window
            for _, win in ipairs(windows) do
                if win.index == winIndex then
                    -- Extract tab title from window title (format: "Profile — Tab Title")
                    local title = win.title or ""
                    -- Extract the part AFTER the em-dash (tab title comes after profile name)
                    tabTitle = title:match("^" .. profile.name .. "%s*—%s*(.+)$")
                    if not tabTitle or tabTitle == "" then
                        tabTitle = nil
                    end
                    break
                end
            end
            table.insert(activeProfiles, {profile = profile, lastUsed = lastUsed, tabTitle = tabTitle})
        else
            table.insert(inactiveProfiles, {profile = profile, lastUsed = lastUsed})
        end
    end
    
    -- Sort both groups by recency if enabled
    if self.config.sortByRecency then
        local function sortByRecency(a, b)
            if a.lastUsed and b.lastUsed then
                return a.lastUsed > b.lastUsed
            elseif a.lastUsed then
                return true
            elseif b.lastUsed then
                return false
            else
                return (a.profile.name or ""):lower() < (b.profile.name or ""):lower()
            end
        end
        
        table.sort(activeProfiles, sortByRecency)
        table.sort(inactiveProfiles, sortByRecency)
    end
    
    -- Build choices
    local choices = {}
    
    -- Add active profiles first
    for _, item in ipairs(activeProfiles) do
        local timeAgo = self:formatTimeAgo(item.lastUsed)
        local tabInfo = (self.config.showTabTitles and item.tabTitle) and (" (" .. item.tabTitle .. ")") or ""
        
        -- Build subtext based on config
        local parts = {}
        if self.config.showWindowStatus then
            table.insert(parts, "Window open" .. tabInfo)
        end
        if self.config.showLastUsed and timeAgo then
            table.insert(parts, "Last used: " .. timeAgo)
        end
        local subText = table.concat(parts, " • ")
        
        -- Create colored pill image using config dimensions
        local image = nil
        if item.profile.color then
            image = self.detector:createColoredImage(
                item.profile.color.r,
                item.profile.color.g,
                item.profile.color.b,
                self.config.pill.height,
                self.config.pill.widthRatio,
                self.config.pill.cornerRadiusDivisor
            )
        end
        
        table.insert(choices, {
            text = item.profile.name,
            subText = subText,
            uuid = item.profile.uuid,
            profile = item.profile,
            image = image
        })
    end
    
    -- Add inactive profiles (no separator)
    for _, item in ipairs(inactiveProfiles) do
        local timeAgo = self:formatTimeAgo(item.lastUsed)
        
        -- Build subtext based on config
        local parts = {}
        if self.config.showWindowStatus then
            table.insert(parts, "Will create new window")
        end
        if self.config.showLastUsed and timeAgo then
            table.insert(parts, "Last used: " .. timeAgo)
        end
        local subText = table.concat(parts, " • ")
        
        -- Create colored pill image using config dimensions
        local image = nil
        if item.profile.color then
            image = self.detector:createColoredImage(
                item.profile.color.r,
                item.profile.color.g,
                item.profile.color.b,
                self.config.pill.height,
                self.config.pill.widthRatio,
                self.config.pill.cornerRadiusDivisor
            )
        end
        
        table.insert(choices, {
            text = item.profile.name,
            subText = subText,
            uuid = item.profile.uuid,
            profile = item.profile,
            image = image
        })
    end
    
    self.chooser:choices(choices)
    self.chooser:show()
end

function obj:onProfileSelected(choice)
    if not choice or not choice.profile then return end  -- Handle separator or nil selection
    
    -- Record that this profile was just used
    self.profileLastUsed[choice.profile.uuid] = os.time()
    
    local success = self:switchToProfile(choice.profile)
    
    if success then
        hs.alert.show("Switched to: " .. choice.text, 2)
    else
        hs.alert.show("Failed to switch to: " .. choice.text, 3)
    end
end

function obj:switchToProfile(profile)
    local profileName = profile.name
    local menuName = profile.menuName  -- Full menu item name for creating windows
    
    -- Ensure Safari is running
    if not self.windowManager:isSafariRunning() then
        self.windowManager:launchSafari()
        hs.timer.usleep(1000000) -- 1 second
    end
    
    -- Get current windows
    local windows = self.windowManager:getSafariWindows()
    
    -- Try to find existing window
    if #windows > 0 then
        local targetIndex = self.windowManager:findWindowWithProfile(profileName, windows)
        
        if targetIndex then
            return self.windowManager:activateWindow(targetIndex)
        end
    end
    
    -- Create new window with profile (using menuName to match menu item)
    return self.windowManager:createWindowWithProfile(profileName, menuName)
end

return obj
