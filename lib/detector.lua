local detector = {}

detector.safariProfilesDir = os.getenv("HOME") ..
    "/Library/Containers/com.apple.Safari/Data/Library/Safari/Profiles/"
detector.safariTabsDB = os.getenv("HOME") ..
    "/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db"

-- Color cache - cleared only when profile count changes
detector.colorCache = {}
detector.lastProfileCount = 0

function detector:isSafariRunning()
    local apps = hs.application.applicationsForBundleID("com.apple.Safari")
    return #apps > 0
end

function detector:extractProfileName(menuItem)
    local name = menuItem:match("^New%s+(.-)%s+Window$")
              or menuItem:match("^Open%s+(.-)%s+Tab$")
              or menuItem:match("^Open%s+(.-)%s+Window$")

    if name then
        return name
    end
    return menuItem
end

function detector:createColoredImage(r, g, b, height, widthRatio, cornerRadiusDivisor)
    height = height or 12
    widthRatio = widthRatio or 2
    cornerRadiusDivisor = cornerRadiusDivisor or 5
    
    -- Create a canvas with a pill box (rounded rectangle) - wider than tall
    local width = height * widthRatio
    local canvas = hs.canvas.new({x=0, y=0, w=width, h=height})
    
    -- Add a rounded rectangle (pill shape) with the profile color
    canvas:appendElements({
        type = "rectangle",
        fillColor = {red=r, green=g, blue=b, alpha=1.0},
        frame = {x=2, y=2, w=width-4, h=height-4},
        roundedRectRadii = {xRadius=height/cornerRadiusDivisor, yRadius=height/cornerRadiusDivisor},
        action = "fill"
    })
    
    -- Render to image
    local image = canvas:imageFromCanvas()
    canvas:delete()
    
    return image
end

function detector:parseProfileColorWithPlutil(hexString)
    if not hexString or #hexString == 0 then
        return nil
    end
    
    -- Full paths, piped command: hex → binary → plutil parse
    local cmd = string.format(
        'echo "%s" | /usr/bin/xxd -r -p | /usr/bin/plutil -p - 2>/dev/null',
        hexString
    )
    
    local handle = io.popen(cmd)
    local output = ""
    if handle then
        output = handle:read("*a") or ""
        handle:close()
    end
    
    -- Silent failure
    if #output == 0 or output:match("error") then
        return nil
    end
    
    -- Parse plutil output: look for color name at index 2, RGB at indices 3,4,5
    local colorName = output:match('2%s*=>%s*"([^"]+)"')
    local r = tonumber(output:match('3%s*=>%s*([0-9.]+)'))
    local g = tonumber(output:match('4%s*=>%s*([0-9.]+)'))
    local b = tonumber(output:match('5%s*=>%s*([0-9.]+)'))
    
    if colorName and r and g and b then
        return {name = colorName, r = r, g = g, b = b}
    end
    
    return nil
end

function detector:getProfileColor(profileUuid, hexString)
    -- Return cached color if available
    if self.colorCache[profileUuid] then
        return self.colorCache[profileUuid]
    end
    
    -- Parse with plutil
    local color = self:parseProfileColorWithPlutil(hexString)
    if color then
        self.colorCache[profileUuid] = color
    end
    
    return color
end

function detector:shouldClearCache(currentCount)
    if currentCount ~= self.lastProfileCount then
        self.colorCache = {}
        self.lastProfileCount = currentCount
    end
end

function detector:getProfileNamesFromDB()
    local cmd = string.format(
        'sqlite3 "%s" "SELECT b.external_uuid, b.title, hex(s.value) FROM settings s ' ..
        'JOIN bookmarks b ON s.parent = b.id WHERE s.key = \'ProfileColor\'"',
        detector.safariTabsDB
    )

    local output, status, _, rc = hs.execute(cmd)
    
    if not status or rc ~= 0 then
        return {}, {}
    end

    local names = {}
    local colors = {}
    for line in output:gmatch("[^\r\n]+") do
        local uuid, name, colorHex = line:match("^([^|]+)|([^|]+)|(.+)$")
        if uuid and name then
            local upperUuid = uuid:upper()
            names[upperUuid] = name
            -- Use cached/parsed color
            colors[upperUuid] = self:getProfileColor(upperUuid, colorHex)
        end
    end
    
    return names, colors
end

function detector:getProfileDirectories()
    local profiles = {}

    local ok, iter, dirObj = pcall(hs.fs.dir, detector.safariProfilesDir)
    if not ok then
        return profiles, "Permission denied"
    end
    
    if not iter then
        return profiles, "Directory not accessible"
    end

    for entry in iter, dirObj do
        if entry ~= "." and entry ~= ".." then
            local fullPath = detector.safariProfilesDir .. entry
            local attrs = hs.fs.attributes(fullPath)
            if attrs and attrs.mode == "directory" then
                table.insert(profiles, {
                    uuid = entry:upper(),
                    id = entry,
                    path = fullPath
                })
            end
        end
    end
    
    return profiles, nil
end

function detector:getProfilesFromMenu()
    if not self:isSafariRunning() then
        return {}
    end

    local script = [[
        tell application "System Events"
            tell process "Safari"
                tell menu bar 1
                    tell menu bar item "File"
                        tell menu 1
                            tell menu item "New Window"
                                tell menu 1
                                    set subMenuItems to name of every menu item
                                    set profileList to {}
                                    set resultString to ""
                                    repeat with itemName in subMenuItems
                                        set itemNameStr to itemName as string
                                        if itemNameStr is not "" and itemNameStr is not "New Window" and itemNameStr is not "New Empty Tab" and itemNameStr does not contain "New Private Window" and itemNameStr does not start with "-" then
                                            set end of profileList to itemNameStr
                                        end if
                                    end repeat
                                    set listCount to count of profileList
                                    repeat with i from 1 to listCount
                                        set resultString to resultString & (item i of profileList)
                                        if i < listCount then
                                            set resultString to resultString & "|"
                                        end if
                                    end repeat
                                    return resultString
                                end tell
                            end tell
                        end tell
                    end tell
                end tell
            end tell
        end tell
    ]]

    local ok, result = hs.osascript.applescript(script)
    if not ok or not result or result == "" then
        return {}
    end

    local profiles = {}
    for menuName in tostring(result):gmatch("([^|]+)") do
        menuName = menuName:match("^%s*(.-)%s*$")
        if menuName and menuName ~= "" then
            local profileName = self:extractProfileName(menuName)
            local fakeUuid = string.format("%08X-%04X-%04X-%04X-%012X",
                math.random(0, 0xFFFFFFFF),
                math.random(0, 0xFFFF),
                math.random(0, 0xFFFF),
                math.random(0, 0xFFFF),
                math.random(0, 0xFFFFFFFFFFFF)
            )
            table.insert(profiles, {
                uuid = fakeUuid,
                id = fakeUuid,
                name = profileName,
                menuName = menuName,
                path = nil
            })
        end
    end

    return profiles
end

function detector:detectProfiles()
    local detectionMethod = "database"
    
    local dbNames, dbColors = self:getProfileNamesFromDB()
    local dirs, dirError = self:getProfileDirectories()
    
    -- Clear cache only if profile count changed
    self:shouldClearCache(#dirs)
    
    local dbFailed = (#dbNames == 0 and #dirs == 0)
    if dbFailed then
        detectionMethod = "menu (fallback)"
    end

    local profiles = {}
    
    for _, dir in ipairs(dirs) do
        local name = dbNames[dir.uuid]
        local colorInfo = dbColors[dir.uuid]
        
        if name then
            table.insert(profiles, {
                id = dir.id,
                uuid = dir.uuid,
                name = name,
                color = colorInfo,
                path = dir.path
            })
        end
    end

    if #profiles == 0 then
        profiles = self:getProfilesFromMenu()
        detectionMethod = "menu"
    end

    table.sort(profiles, function(a, b)
        local aIsNamed = a.name and #a.name < 36
        local bIsNamed = b.name and #b.name < 36
        if aIsNamed ~= bIsNamed then return aIsNamed end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    return profiles, detectionMethod
end

return detector
