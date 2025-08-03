# Hammerflow
A Hammerspoon Spoon to enable a global leader key for your mac that's easy to configure and fun to play with!

## Quick Start

1. Clone the Hammerflow spoon:
```bash
git clone https://github.com/saml-dev/Hammerflow.spoon.git ~/.hammerspoon/Spoons/Hammerflow.spoon
```
2. In init.lua load Hammerflow and pass a list of config files for it to search for. It takes absolute paths and paths relative to the Hammerspoon config dir, usually ~/.hammerspoon
```lua
hs.loadSpoon("Hammerflow")
spoon.Hammerflow.loadFirstValidTomlFile({
    "home.toml",
    "work.toml",
    "Spoons/Hammerflow.spoon/sample.toml"
})

-- optionally register custom functions.
-- registerFunctions takes 1 or more tables.
-- each table contains functions that can be 
-- called from your toml config using the
-- function: prefix, e.g.
--   h = "function:hi"
local fileFuncs = require("files.lua")
spoon.Hammerflow.registerFunctions(
    fileFuncs, 
    { ["hi"] = function() hs.alert("hi") end }
)

-- optionally respect auto_reload setting in the toml config.
if spoon.Hammerflow.auto_reload then
    hs.loadSpoon("ReloadConfiguration")
    -- set any paths for auto reload
    -- spoon.ReloadConfiguration.watch_paths = {hs.configDir, "/path/to/my/configs/"}
    spoon.ReloadConfiguration:start()
end
```
3. (Recommended) Use Karabiner Elements to remap Right Command to f18 for a dedicated leader key.
4. Explore sample.toml to see what you can do and try out some of the default actions.
5. Create your own toml config and personalize to your hearts content!

## UI Formatting

Customize the format of your Hammerflow UI using standard Hammerspoon formatting syntax and separate from.

> [!IMPORTANT]
> Any formatting must be registered before loading your toml configuration.

```lua
hs.loadSpoon("Hammerflow")
-- optionally set ui format (must be done before loading toml config)
-- 🧛 Dracula inspired theme
spoon.Hammerflow.registerFormat({
	atScreenEdge = 2,
	fillColor = { alpha = .875, hex = "282b36" },
	padding = 18,
	radius = 12,
	strokeColor = { alpha = .875, hex = "f1fa8b" },
	textColor = { alpha = 1, hex = "bd93f9" },
	textStyle = {
		paragraphStyle = { lineSpacing = 6 },
		shadow = { offset = { h = -1, w = 1 }, blurRadius = 10, color = { alpha = .50, white = 0 } }
	},
	strokeWidth = 6,
	textFont = "Monaco",
	textSize = 18,
})
spoon.Hammerflow.loadFirstValidTomlFile({
	"home.toml",
	"work.toml",
	"Spoons/Hammerflow.spoon/sample.toml",
})
```

## Full Documentation
All available options are demonstrated in [sample.toml](./sample.toml). I will create proper documentation soon.

## Quick start
See [Hammerflow.dev](https://hammerflow.dev) for the quick start information.
