---@diagnostic disable: undefined-global

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Hammerflow"
obj.version = "1.0"
obj.author = "Sam Lewis <sam@saml.dev>"
obj.homepage = "https://github.com/saml-dev/Hammerflow.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- State
obj.auto_reload = false
obj._userFunctions = {}
obj._apps = {}

-- lets us package RecursiveBinder with Hammerflow to include
-- sorting and a bug fix that hasn't been merged upstream yet
-- https://github.com/Hammerspoon/Spoons/pull/333
package.path = package.path .. ";" .. hs.configdir .. "/Spoons/Hammerflow.spoon/Spoons/?.spoon/init.lua"
hs.loadSpoon("RecursiveBinder")

local function full_path(rel_path)
  local current_file = debug.getinfo(2, "S").source:sub(2) -- Get the current file's path
  local current_dir = current_file:match("(.*/)") or "."   -- Extract the directory
  return current_dir .. rel_path
end
local function loadfile_relative(path)
  local full_path = full_path(path)
  local f, err = loadfile(full_path)
  if f then
    return f()
  else
    error("Failed to require relative file: " .. full_path .. " - " .. err)
  end
end
local function split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

local toml = loadfile_relative("lib/tinytoml.lua")

local function parseKeystroke(keystroke)
  local parts = {}
  for part in keystroke:gmatch("%S+") do
    table.insert(parts, part)
  end
  local key = table.remove(parts) -- Last part is the key
  return parts, key
end

local function file_exists(name)
  local f = io.open(name, "r")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

-- Action Helpers
local singleKey = spoon.RecursiveBinder.singleKey
local rect = hs.geometry.rect
local move = function(loc)
  return function()
    local w = hs.window.focusedWindow()
    w:move(loc)
    -- for some reason Firefox, and therefore Zen Browser, both
    -- animate when no other apps do, and only change size *or*
    -- position when moved, so it has to be issued twice. 0.2 is
    -- the shortest delay that works consistently.
    if hs.application.frontmostApplication():bundleID() == "app.zen-browser.zen" or
        hs.application.frontmostApplication():bundleID() == "org.mozilla.firefox" then
      os.execute("sleep 0.2")
      w:move(loc)
    end
  end
end
local open = function(link)
  return function() os.execute(string.format("open \"%s\"", link)) end
end
local raycast = function(link)
  -- raycast needs -g to keep current app as "active" for
  -- pasting from emoji picker and window management
  return function() os.execute(string.format("open -g %s", link)) end
end
local text = function(s)
  return function() hs.eventtap.keyStrokes(s) end
end
local keystroke = function(keystroke)
  local mods, key = parseKeystroke(keystroke)
  return function() hs.eventtap.keyStroke(mods, key) end
end
local cmd = function(cmd)
  return function() os.execute(cmd .. " &") end
end
local code = function(arg) return cmd("open -a 'Visual Studio Code' " .. arg) end
local launch = function(app)
  return function() hs.application.launchOrFocus(app) end
end
local hs_run = function(lua)
  return function() load(lua)() end
end
local userFunc = function(funcKey)
  local args = nil
  -- if funcKey has | in it, split on it. first is function name, rest are args for that function
  if funcKey:find("|") then
    local sp = split(funcKey, "|")
    funcKey = table.remove(sp, 1)
    args = sp
  end
  return function()
    if obj._userFunctions[funcKey] then
      obj._userFunctions[funcKey](table.unpack(args or {}))
    else
      hs.alert("Unknown function " .. funcKey, 3)
    end
  end
end
local function isApp(app)
  return function()
    local frontApp = hs.application.frontmostApplication()
    local title = frontApp:title():lower()
    local bundleID = frontApp:bundleID():lower()
    app = app:lower()
    return title == app or bundleID == app
  end
end

-- window management presets
local windowLocations = {
  ["left-half"] = move(hs.layout.left50),
  ["center-half"] = move(rect(.25, 0, .5, 1)),
  ["right-half"] = move(hs.layout.right50),
  ["first-quarter"] = move(hs.layout.left25),
  ["second-quarter"] = move(rect(.25, 0, .25, 1)),
  ["third-quarter"] = move(rect(.5, 0, .25, 1)),
  ["fourth-quarter"] = move(hs.layout.right25),
  ["left-third"] = move(rect(0, 0, 1 / 3, 1)),
  ["center-third"] = move(rect(1 / 3, 0, 1 / 3, 1)),
  ["right-third"] = move(rect(2 / 3, 0, 1 / 3, 1)),
  ["top-half"] = move(rect(0, 0, 1, .5)),
  ["bottom-half"] = move(rect(0, .5, 1, .5)),
  ["top-left"] = move(rect(0, 0, .5, .5)),
  ["top-right"] = move(rect(.5, 0, .5, .5)),
  ["bottom-left"] = move(rect(0, .5, .5, .5)),
  ["bottom-right"] = move(rect(.5, .5, .5, .5)),
  ["maximized"] = move(hs.layout.maximized),
  ["fullscreen"] = function() hs.window.focusedWindow():toggleFullScreen() end
}

-- helper functions
local function startswith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function postfix(s)
  --  return the string after the colon
  return s:sub(s:find(":") + 1)
end

local function getActionAndLabel(s)
  if s:find("^http[s]?://") then
    return open(s), s:sub(5, 5) == "s" and s:sub(9) or s:sub(8)
  elseif s == "reload" then
    return function()
      hs.reload()
      hs.console.clearConsole()
    end, s
  elseif startswith(s, "raycast://") then
    return raycast(s), s
  elseif startswith(s, "hs:") then
    return hs_run(postfix(s)), s
  elseif startswith(s, "cmd:") then
    local arg = postfix(s)
    return cmd(arg), arg
  elseif startswith(s, "input:") then
    local remaining = postfix(s)
    local _, label = getActionAndLabel(remaining)
    return function()
      -- user input takes focus and doesn't return it
      local focusedWindow = hs.window.focusedWindow()
      local button, userInput = hs.dialog.textPrompt("", "", "", "Submit", "Cancel")
      -- restore focus
      focusedWindow:focus()

      if button == "Cancel" then return end

      -- replace text and execute remaining action
      local replaced = string.gsub(remaining, "{input}", userInput)
      local action, _ = getActionAndLabel(replaced)
      action()
    end, label
  elseif startswith(s, "shortcut:") then
    local arg = postfix(s)
    return keystroke(arg), arg
  elseif startswith(s, "function:") then
    local funcKey = postfix(s)
    return userFunc(funcKey), funcKey .. "()"
  elseif startswith(s, "code:") then
    local arg = postfix(s)
    return code(arg), "code " .. arg
  elseif startswith(s, "text:") then
    local arg = postfix(s)
    return text(arg), arg
  elseif startswith(s, "window:") then
    local loc = postfix(s)
    if windowLocations[loc] then
      return windowLocations[loc], s
    else
      -- regex to parse e.g. 0,0,.5,1 for left half of screen
      local x, y, w, h = loc:match("^([%.%d]+),%s*([%.%d]+),%s*([%.%d]+),%s*([%.%d]+)$")
      if not x then
        hs.alert('Invalid window location: "' .. loc .. '"', nil, nil, 5)
        return
      end
      return move(rect(tonumber(x), tonumber(y), tonumber(w), tonumber(h))), s
    end
    return
  else
    return launch(s), s
  end
end

function obj.loadFirstValidTomlFile(paths)
  -- parse TOML file
  local configFile = nil
  local configFileName = ""
  local searchedPaths = {}
  for _, path in ipairs(paths) do
    if not startswith(path, "/") then
      path = hs.configdir .. "/" .. path
    end
    table.insert(searchedPaths, path)
    if file_exists(path) then
      if pcall(function() toml.parse(path) end) then
        configFile = toml.parse(path)
        configFileName = path
        break
      else
        hs.notify.show("Hammerflow", "Parse error", path .. "\nCheck for duplicate keys like s and [s]")
      end
    end
  end
  if not configFile then
    hs.alert("No toml config found! Searched for: " .. table.concat(searchedPaths, ', '), 5)
    obj.auto_reload = true
    return
  end
  if configFile.leader_key == nil or configFile.leader_key == "" then
    hs.alert("You must set leader_key at the top of " .. configFileName .. ". Exiting.", 5)
    return
  end

  -- settings
  local leader_key = configFile.leader_key or "f18"
  local leader_key_mods = configFile.leader_key_mods or ""
  if configFile.auto_reload == nil or configFile.auto_reload then
    obj.auto_reload = true
  end
  if configFile.toast_on_reload == true then
    hs.alert('🔁 Reloaded config')
  end
  if configFile.show_ui == false then
    spoon.RecursiveBinder.showBindHelper = false
  end

  -- clear settings from table so we don't have to account
  -- for them in the recursive processing function
  configFile.leader_key = nil
  configFile.leader_key_mods = nil
  configFile.auto_reload = nil
  configFile.toast_on_reload = nil
  configFile.show_ui = nil

  local function parseKeyMap(config)
    local keyMap = {}
    local conditionalActions = nil
    for k, v in pairs(config) do
      if k == "label" then
        -- continue
      elseif k == "apps" then
        for shortName, app in pairs(v) do
          obj._apps[shortName] = app
        end
      elseif string.find(k, "_") then
        local key = k:sub(1, 1)
        local cond = k:sub(3)
        if conditionalActions == nil then conditionalActions = {} end
        local actionString = v
        if type(v) == "table" then
          actionString = v[1]
        end
        if conditionalActions[key] then
          conditionalActions[key][cond] = getActionAndLabel(actionString)
        else
          conditionalActions[key] = { [cond] = getActionAndLabel(actionString) }
        end
      elseif type(v) == "string" then
        local action, label = getActionAndLabel(v)
        keyMap[singleKey(k, label)] = action
      elseif type(v) == "table" and v[1] then
        local action, defaultLabel = getActionAndLabel(v[1])
        keyMap[singleKey(k, v[2] or defaultLabel)] = action
      else
        keyMap[singleKey(k, v.label or k)] = parseKeyMap(v)
      end
    end

    -- parse labels and default action for conditional actions
    local conditionalLabels = {}
    if conditionalActions ~= nil then
      -- get the default action if it exists
      for key_, value_ in pairs(keyMap) do
        if conditionalActions[key_[2]] then
          conditionalActions[key_[2]]["_"] = value_
          keyMap[key_] = nil
          conditionalLabels[key_[2]] = key_[3]
        end
      end
      -- add conditionalActions to keyMap
      for key_, value_ in pairs(conditionalActions) do
        keyMap[singleKey(key_, conditionalLabels[key_] or "conditional")] = function()
          local fallback = true
          for cond, fn in pairs(value_) do
            if (obj._userFunctions[cond] and obj._userFunctions[cond]())
                or (obj._userFunctions[cond] == nil and isApp(cond)())
            then
              fn()
              fallback = false
              break
            end
          end
          if fallback and value_["_"] then
            value_["_"]()
          end
        end
      end
    end

    -- add apps to userFunctions if there isn't a function with the same name
    for k, v in pairs(obj._apps) do
      if obj._userFunctions[k] == nil then
        obj._userFunctions[k] = isApp(v)
      end
    end

    return keyMap
  end

  local keys = parseKeyMap(configFile)
  hs.hotkey.bind(leader_key_mods, leader_key, spoon.RecursiveBinder.recursiveBind(keys))
end

function obj.registerFunctions(...)
  for _, funcs in pairs({ ... }) do
    for k, v in pairs(funcs) do
      obj._userFunctions[k] = v
    end
  end
end

return obj
