package.cpath = package.cpath ..
    ";/Users/monashsapkota/.vscode/extensions/tangzx.emmylua-0.9.20-darwin-arm64/debugger/emmy/mac/arm64/emmy_core.dylib"
local dbg = require("emmy_core")
dbg.tcpListen("localhost", 9966)
---@diagnostic disable: undefined-global

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Hammerflow"
obj.version = "1.0"
obj.author = "Sam Lewis <sam@saml.dev>"
obj.homepage = "https://github.com/saml-dev/Hammerflow.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local WILDCARD_ACTION_MARKER_KEY = "__HAMMERFLOW_WILDCARD_ACTION__"

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
    return function()
        os.execute(full_command)
    end
    -- return function() os.execute(cmd .. " &") end
end
local code = function(arg) return cmd("open -a 'Visual Studio Code' " .. arg) end
local launch = function(app)
    return function() hs.application.launchOrFocus(app) end
end
local hs_run = function(lua)
    return function() load(lua)() end
end

local userFunc = function(funcKeyString, pressedKeyValue)
    local actualFuncName = funcKeyString
    local argsTable = {}

    if funcKeyString:find("|") then
        local parts = split(funcKeyString, "|")
        actualFuncName = table.remove(parts, 1)
        argsTable = parts
    end


    if pressedKeyValue then -- For {KEY} in function name part
        actualFuncName = string.gsub(actualFuncName, "{KEY}", pressedKeyValue)
    end
    if pressedKeyValue and #argsTable > 0 then -- For {KEY} in args part
        for i, arg_val in ipairs(argsTable) do
            argsTable[i] = string.gsub(arg_val, "{KEY}", pressedKeyValue)
        end
    end

    return function()
        if obj._userFunctions[actualFuncName] then
            obj._userFunctions[actualFuncName](table.unpack(argsTable))
        else
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

local function getActionAndLabel(actionString)
    local actionExecutor, label

    local createAction = function(originalActionConstructor, templateString, defaultLabel, isUserFuncFlag)
        label = defaultLabel or templateString

        return function(actionPressedKeyValue)
            -- hs.alert.show("HF_CREATE_ACTION_EXECUTOR",
            --     "Template: " .. templateString ..
            --     "\nisUserFuncFlag: " .. tostring(isUserFuncFlag), 7) -- DURATION 7

            local finalStringForAction = templateString
            if actionPressedKeyValue then
                finalStringForAction = string.gsub(templateString, "{KEY}", actionPressedKeyValue)
            end
            -- hs.alert.show("HF_CREATE_ACTION_EXECUTOR",
            --     "FinalStringForAction: " .. finalStringForAction, 7) -- DURATION 7

            if isUserFuncFlag then
                userFunc(finalStringForAction, actionPressedKeyValue)()
            else
                originalActionConstructor(finalStringForAction)()
            end
        end
    end

    if actionString:find("^http[s]?://") then
        local displayLabel = actionString:sub(5, 5) == "s" and actionString:sub(9) or actionString:sub(8)
        if string.len(displayLabel) > 20 then displayLabel = displayLabel:sub(1, 18) .. ".." end
        actionExecutor = createAction(open, actionString, displayLabel, false)
    elseif actionString == "reload" then
        label = actionString
        actionExecutor = function(actionPressedKeyValue)
            if actionPressedKeyValue then
                hs.alert.show("Hammerflow: Warning",
                    "{KEY} placeholder ignored for 'reload' action.", 2)
            end
            hs.reload()
            hs.console.clearConsole()
        end
    elseif startswith(actionString, "raycast://") then
        local displayLabel = actionString
        if string.len(displayLabel) > 20 then displayLabel = displayLabel:sub(1, 18) .. ".." end
        actionExecutor = createAction(raycast, actionString, displayLabel, false)
    elseif startswith(actionString, "hs:") then
        local luaCodeTemplate = postfix(actionString)
        actionExecutor = createAction(hs_run, luaCodeTemplate, "hs:" .. luaCodeTemplate, false)
    elseif startswith(actionString, "cmd:") then
        local cmdTemplate = postfix(actionString)
        actionExecutor = createAction(cmd, cmdTemplate, "cmd:" .. cmdTemplate, false)
    elseif startswith(actionString, "input:") then
        local remainingTemplate = postfix(actionString)
        local _, tempDisplayLabel = getActionAndLabel(string.gsub(remainingTemplate, "{input}", "<?>"))
        label = "input->" .. tempDisplayLabel
        actionExecutor = function(actionPressedKeyValue)
            local finalRemainingTemplate = remainingTemplate
            if actionPressedKeyValue then
                finalRemainingTemplate = string.gsub(remainingTemplate, "{KEY}", actionPressedKeyValue)
            end
            local focusedWindow = hs.window.focusedWindow()
            local button, userInput = hs.dialog.textPrompt("Hammerflow Input",
                finalRemainingTemplate:gsub("{input}", "<?>"), "", "Submit", "Cancel")
            if focusedWindow then focusedWindow:focus() end
            if button == "Cancel" or not userInput then return end
            local actionStringWithInput = string.gsub(finalRemainingTemplate, "{input}", userInput)
            local finalInnerActionExecutor, _ = getActionAndLabel(actionStringWithInput)
            finalInnerActionExecutor()
        end
    elseif startswith(actionString, "shortcut:") then
        local shortcutTemplate = postfix(actionString)
        actionExecutor = createAction(keystroke, shortcutTemplate, "shortcut:" .. shortcutTemplate, false)
    elseif startswith(actionString, "function:") then
        local funcKeyAndArgsTemplate = postfix(actionString)
        actionExecutor = createAction(nil, funcKeyAndArgsTemplate, "fn:" .. funcKeyAndArgsTemplate, true)
    elseif startswith(actionString, "code:") then
        local argTemplate = postfix(actionString)
        actionExecutor = createAction(code, argTemplate, "code:" .. argTemplate, false)
    elseif startswith(actionString, "text:") then
        local textTemplate = postfix(actionString)
        actionExecutor = createAction(text, textTemplate, "text:" .. textTemplate, false)
    elseif startswith(actionString, "window:") then
        local locTemplate = postfix(actionString)
        label = "win:" .. locTemplate
        actionExecutor = function(actionPressedKeyValue)
            local finalLoc = locTemplate
            if actionPressedKeyValue then
                finalLoc = string.gsub(locTemplate, "{KEY}", actionPressedKeyValue)
            end
            if windowLocations[finalLoc] then
                windowLocations[finalLoc]()
            else
                local x, y, w, h = finalLoc:match("^([%.%d]+),%s*([%.%d]+),%s*([%.%d]+),%s*([%.%d]+)$")
                if not x then
                    hs.alert.show('Hammerflow: Invalid window location', '"' .. finalLoc .. '"', 3)
                    return
                end
                move(rect(tonumber(x), tonumber(y), tonumber(w), tonumber(h)))()
            end
        end
    else
        local appNameTemplate = actionString
        actionExecutor = createAction(launch, appNameTemplate, appNameTemplate, false)
    end
    return actionExecutor, label
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

    spoon.RecursiveBinder.helperFormat = hs.alert.defaultStyle

    -- clear settings from table so we don't have to account
    -- for them in the recursive processing function
    configFile.leader_key = nil
    configFile.leader_key_mods = nil
    configFile.auto_reload = nil
    configFile.toast_on_reload = nil
    configFile.show_ui = nil


    local function parseKeyMap(config)
        local keyMap = {}
        local conditionalActions = nil -- Keep existing conditional logic

        for k, v in pairs(config) do
            if k == "label" then
                -- continue
            elseif k == "apps" then
                for shortName, app in pairs(v) do
                    obj._apps[shortName] = app
                end
            elseif k == WILDCARD_ACTION_MARKER_KEY then -- OUR NEW WILDCARD KEY
                if type(v) == "string" then
                    local actionExecutor, label = getActionAndLabel(v)
                    keyMap[WILDCARD_ACTION_MARKER_KEY] = { actionExecutor, label }
                elseif type(v) == "table" and v[1] then -- Allow ["action_string", "custom label for any"]
                    local actionExecutor, defaultLabel = getActionAndLabel(v[1])
                    keyMap[WILDCARD_ACTION_MARKER_KEY] = { actionExecutor, v[2] or defaultLabel }
                else
                    hs.alert(
                        "Hammerflow: Invalid format for " ..
                        WILDCARD_ACTION_MARKER_KEY .. ". Expected string or table [action, label].", 3)
                end
            elseif string.find(k, "_") and not (k == WILDCARD_ACTION_MARKER_KEY) then -- Existing conditional logic
                local key = k:sub(1, 1)
                local cond = k:sub(3)
                if conditionalActions == nil then conditionalActions = {} end
                local actionString = v
                if type(v) == "table" then
                    actionString = v[1] -- Assuming the first element is the action string
                end
                -- getActionAndLabel returns actionExecutor, label
                local actionExecutorForCond, labelForCond = getActionAndLabel(actionString)
                if conditionalActions[key] then
                    conditionalActions[key][cond] = { actionExecutorForCond, labelForCond }
                else
                    conditionalActions[key] = { [cond] = { actionExecutorForCond, labelForCond } }
                end
            elseif type(v) == "string" then
                local actionExecutor, label = getActionAndLabel(v)
                keyMap[singleKey(k, label)] = actionExecutor
            elseif type(v) == "table" and v[1] then -- Array form: ["action_string", "Custom Label"]
                local actionExecutor, defaultLabel = getActionAndLabel(v[1])
                keyMap[singleKey(k, v[2] or defaultLabel)] = actionExecutor
            else -- Nested table for sub-menu
                keyMap[singleKey(k, v.label or k)] = parseKeyMap(v)
            end
        end

        -- Process conditional actions (modified to use actionExecutor)
        if conditionalActions ~= nil then
            local conditionalKeyMapEntries = {} -- Store resolved conditional actions here

            for keyChar, conditions in pairs(conditionalActions) do
                local defaultActionExecutor = nil
                local defaultLabel = keyChar .. " (cond)"
                local specificKeyDef = nil -- To find the original singleKey definition for the label

                -- Check if there's a non-conditional entry for this keyChar to get its label and default action
                for sk, actExec in pairs(keyMap) do
                    if type(sk) == "table" and sk[2] == keyChar then -- sk is {mods, key, label}
                        defaultActionExecutor = actExec              -- This is an actionExecutor
                        defaultLabel = sk[3]
                        specificKeyDef = sk
                        break
                    end
                end
                if specificKeyDef then keyMap[specificKeyDef] = nil end -- Remove original, will be replaced by conditional wrapper

                -- Prepare the conditional action executor
                conditionalKeyMapEntries[singleKey(keyChar, defaultLabel)] = function(pressedKeyValue) -- Wrapper takes pressedKeyValue
                    -- Note: conditional logic itself doesn't use pressedKeyValue from wildcard.
                    -- The *actions within* the conditions might, if their templates used {KEY}.
                    if pressedKeyValue then
                        hs.alert.show("Hammerflow: Warning",
                            "{KEY} not directly applicable to conditional branches, but actions within might use it.", 2)
                    end

                    local fallback = true
                    for condName, actionData in pairs(conditions) do
                        local actionToRun = actionData[1] -- This is an actionExecutor
                        local actionLabel = actionData[2] -- Not used here, but good to have

                        local conditionMet = false
                        if obj._userFunctions[condName] and obj._userFunctions[condName]() then
                            conditionMet = true
                        elseif obj._userFunctions[condName] == nil and isApp(condName)() then
                            conditionMet = true
                        end

                        if conditionMet then
                            actionToRun() -- Call the actionExecutor (it will handle its own {KEY} if it was a template)
                            fallback = false
                            break
                        end
                    end
                    if fallback and defaultActionExecutor then
                        defaultActionExecutor() -- Call the default actionExecutor
                    elseif fallback then
                        hs.alert("Hammerflow: No condition met for '" .. keyChar .. "' and no default action.", 2)
                    end
                end
            end
            -- Add resolved conditional actions to keyMap
            for k_cond, v_cond_exec in pairs(conditionalKeyMapEntries) do
                keyMap[k_cond] = v_cond_exec
            end
        end

        -- Add apps to userFunctions if there isn't a function with the same name
        for k_app, v_app in pairs(obj._apps) do
            if obj._userFunctions[k_app] == nil then
                obj._userFunctions[k_app] = isApp(v_app)
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
            hs.alert.show("🚨Aerospace Functions Loading")
        end
    end
end

return obj
