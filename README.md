# SafariProfileSwitcher

A [Hammerspoon](https://www.hammerspoon.org/) Spoon that provides a hotkey-activated chooser interface for quickly switching between Safari profiles. It automatically detects your Safari profiles and allows you to switch to existing windows or create new ones with the selected profile.

> **Disclaimer:** This Spoon was created with the assistance of Generative AI.

## Features

- 🔥 **Hotkey-activated chooser** - Press `⌥A` (or your custom hotkey) to open the profile switcher
- 🎨 **Visual profile colors** - Shows colored pills matching your Safari profile colors
- 🪟 **Window awareness** - Detects which profiles already have open windows
- ⏱️ **Recency sorting** - Recently used profiles appear at the top
- 📑 **Tab title display** - Shows the current tab title for open windows
- 🔄 **Auto-refresh** - Automatically detects profile changes when Safari restarts
- 🚀 **Smart switching** - Switches to existing windows or creates new ones as needed

## Requirements

- macOS 10.15+ (Catalina or later)
- [Hammerspoon](https://www.hammerspoon.org/) installed
- Safari with configured profiles

## Installation

### 1. Install Hammerspoon

```bash
brew install --cask hammerspoon
```

Or download from [hammerspoon.org](https://www.hammerspoon.org/).

### 2. Install SafariProfileSwitcher

#### Option A: Clone to Spoons directory

```bash
mkdir -p ~/.hammerspoon/Spoons
cd ~/.hammerspoon/Spoons
git clone https://github.com/YOUR_USERNAME/SafariProfileSwitcher.spoon.git
```

#### Option B: Manual download

1. Download the latest release
2. Extract the zip file
3. Rename the folder to `SafariProfileSwitcher.spoon`
4. Move it to `~/.hammerspoon/Spoons/`

Your directory structure should look like:

```
~/.hammerspoon/
├── Spoons/
│   └── SafariProfileSwitcher.spoon/
│       ├── init.lua
│       └── lib/
│           ├── detector.lua
│           └── window_manager.lua
└── init.lua
```

### 3. Load the Spoon in Hammerspoon

Edit your `~/.hammerspoon/init.lua` file and add:

```lua
-- Load SafariProfileSwitcher
hs.loadSpoon("SafariProfileSwitcher")

-- Optional: Configure before starting
spoon.SafariProfileSwitcher:configure({
    hotkey = {mods = {"alt"}, key = "A"},  -- Change to your preferred hotkey
    showTabTitles = true,
    sortByRecency = true
})

-- Start the spoon
spoon.SafariProfileSwitcher:start()
```

### 4. Reload Hammerspoon Configuration

Click the Hammerspoon menu bar icon and select **"Reload Config"**, or run:

```lua
hs.reload()
```

## Required Permissions

This Spoon requires several macOS permissions to function correctly:

### 1. Accessibility Permissions (Required)

Hammerspoon needs Accessibility access to control Safari windows and read menu items.

**To grant:**
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the **+** button
3. Select **Hammerspoon** from Applications
4. Ensure the toggle is **ON**

### 2. Full Disk Access (Recommended)

Required to read Safari's profile database and detect profile colors/names automatically.

**To grant:**
1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Select **Hammerspoon**
4. Ensure the toggle is **ON**

> **Note:** Without Full Disk Access, the Spoon can still work using menu-based detection (slower and without color information).

### 3. Automation Permissions

Required for AppleScript control of Safari.

**First-time setup:**
1. The first time you use the Spoon, macOS will prompt:
   - "Hammerspoon wants to control Safari"
2. Click **"Allow"** or **"OK"**

If you miss the prompt:
1. Open **System Settings** → **Privacy & Security** → **Automation**
2. Find **Hammerspoon**
3. Ensure **Safari** is checked

## Configuration

All configuration is optional. The Spoon works with sensible defaults.

```lua
spoon.SafariProfileSwitcher:configure({
    -- Hotkey to show the chooser
    hotkey = {
        mods = {"alt"},      -- Modifier keys: "cmd", "alt", "ctrl", "shift"
        key = "A"            -- Key to press (single character)
    },
    
    -- Chooser appearance
    chooser = {
        rows = 8,            -- Number of visible rows
        width = 25           -- Width in "Hammerspoon units"
    },
    
    -- Profile color pill appearance
    pill = {
        height = 12,                    -- Pill height in pixels
        widthRatio = 2,                 -- Width = height * widthRatio
        cornerRadiusDivisor = 5         -- Corner radius = height / divisor
    },
    
    -- Feature toggles
    showTabTitles = true,       -- Show current tab title in parentheses
    sortByRecency = true,       -- Sort profiles by last used time
    showLastUsed = true,        -- Show "Last used: X ago" in subtext
    showWindowStatus = true     -- Show "Window open" / "Will create new window"
})
```

### Example: Change Hotkey to Cmd+Shift+S

```lua
spoon.SafariProfileSwitcher:configure({
    hotkey = {mods = {"cmd", "shift"}, key = "S"}
})
```

### Example: Minimal UI (no tab titles, no last used)

```lua
spoon.SafariProfileSwitcher:configure({
    showTabTitles = false,
    showLastUsed = false,
    showWindowStatus = false
})
```

## Usage

1. **Open the chooser**: Press your configured hotkey (default: `⌥A`)
2. **Select a profile**:
   - Type to filter profiles
   - Use `↑`/`↓` arrow keys to navigate
   - Press `Enter` to select
3. **Window behavior**:
   - If the profile has an open window → switches to that window
   - If no window exists → creates a new window with that profile

## Troubleshooting

### "No profiles found" error

1. Ensure Safari is running and has profiles configured
2. Check that Hammerspoon has **Full Disk Access** permission
3. Try restarting Hammerspoon: `hs.reload()`

### "Failed to switch" error

1. Ensure Hammerspoon has **Accessibility** permission
2. Check that Hammerspoon can control Safari in **Automation** permissions
3. Try manually clicking Safari's File menu to verify profiles are accessible

### Profiles not showing colors

Colors are read from Safari's database. If colors don't appear:
1. Ensure **Full Disk Access** is granted
2. Try restarting Safari and Hammerspoon

### Hotkey not working

1. Check if another app is using the same hotkey
2. Try a different key combination in the configuration
3. Ensure Hammerspoon is running (check menu bar icon)

## How It Works

1. **Profile Detection**: Reads Safari's `SafariTabs.db` SQLite database to find profiles and their colors
2. **Window Tracking**: Monitors Safari windows to identify which profile each window belongs to
3. **Profile Switching**: Uses AppleScript to interact with Safari's File menu to create new windows with specific profiles

## File Structure

```
SafariProfileSwitcher.spoon/
├── init.lua           -- Main spoon logic and configuration
└── lib/
    ├── detector.lua   -- Profile detection from database and menus
    └── window_manager.lua -- Safari window management and switching
```

## License

MIT License

## Contributing

Issues and pull requests welcome! Please ensure your code follows the existing style and includes appropriate documentation.

---

**Note:** This is an unofficial tool and is not affiliated with Apple Inc. Safari is a trademark of Apple Inc.
