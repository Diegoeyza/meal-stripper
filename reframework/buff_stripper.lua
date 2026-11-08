--
-- buff_stripper.lua v1.0.0 — strip the ACTIVE meal so you can eat another one
--
-- Purpose (speedrunning): one click removes the current meal buff (stats and
-- food skills go off), so a different meal can be eaten immediately after.
--
-- Scope: meal buff only (app.cHunterMealEffect on the local hunter).
--
-- What it writes (field set proven by reframework/meal_probe.lua on this
-- build):
--     _IsTimerActive=false     _IsEffectActive=false   _DurationTimer=0.0
--     _MaxHealthAdd=0.0        _MaxStaminaAdd=0.0
--     _TempIsTimerActive=false _TempIsEffectActive=false
-- The game does NOT rewrite these every tick: verified at +15/+120 frames,
-- after 40 s in the training grounds, and across a full real quest — so a
-- one-shot strip sticks and eating a new meal afterwards works normally.
--
-- Load: reframework\autorun\ (appears in "Script Generated UI"); reload with
--   REFramework menu -> Script -> Reset scripts (or restart the game).
-- Footprint: no sdk.hook, no per-frame callback — a single UI draw callback.
--   Nothing runs at load and nothing runs until a button is pressed.
--   No config file (single action, no settings).
--
-- Lineage: overall shape (autorun layout, imgui, safe() wrappers, logging)
--   follows hunt_dumper by thieleju (MIT); the field list comes from this
--   repo's own meal_probe dumps. No code from GPL/unlicensed sources.
--
-- Every SDK call is pcall-guarded: this script never throws into the game.
--

local re = re
local sdk = sdk
local log = log
local imgui = imgui

local VERSION = "1.0.0"

-- Re-running the script must not register a second set of callbacks.
local ALREADY_LOADED = _G.BUFF_STRIPPER_LOADED == true
_G.BUFF_STRIPPER_LOADED = true

local lastStatus = "(idle)"
local strippedAt = nil
local saved_values = nil   -- field -> pre-strip value, for Restore

-- ---------------------------------------------------------------------------
-- small helpers (same shapes hunt_dumper and meal_probe prove on this build)
-- ---------------------------------------------------------------------------

local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

local function safe_str(v)
    if v == nil then return nil end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    return tostring(v)
end

local function call_method(obj, name)
    if obj == nil then return nil end
    local v = safe(function() return obj:call(name) end)
    if v ~= nil then return v end
    local td = safe(function() return obj:get_type_definition() end)
    local m = td and safe(function() return td:get_method(name) end)
    if not m then return nil end
    return safe(function() return m:call(obj) end)
end

local function typecall(typeName, methodName, obj)
    local td = safe(sdk.find_type_definition, typeName)
    if not td then return nil end
    local m = safe(function() return td:get_method(methodName .. "()") end)
        or safe(function() return td:get_method(methodName) end)
    if not m then return nil end
    return safe(function() return m:call(obj) end)
end

-- Read an instance field by name through the field descriptor: obj:get_field()
-- returns nil for several Hunter/Wilds structs, get_data(obj) does not.
local function field_value(obj, fieldName)
    if obj == nil then return nil end
    local td = safe(function() return obj:get_type_definition() end)
    if not td then return nil end
    for _, f in ipairs(safe(function() return td:get_fields() end) or {}) do
        if safe(function() return f:get_name() end) == fieldName then
            local is_static = safe(function() return f:is_static() end)
            return safe(function() return f:get_data(is_static and nil or obj) end)
        end
    end
    return nil
end

-- Write an instance field. Two paths, same destination: set_field resolves the
-- field on the object's own type, set_native_field on the type we pass in.
local function write_field(obj, typeName, fieldName, value)
    if obj == nil then return false, "no_object" end
    local ok = safe(function() obj:set_field(fieldName, value) return true end)
    if ok then return true, "set_field" end
    local td = safe(sdk.find_type_definition, typeName)
    if not td then return false, "no_type" end
    local ok2 = safe(function()
        sdk.set_native_field(obj, td, fieldName, value)
        return true
    end)
    return ok2 == true, ok2 and "set_native_field" or "write_failed"
end

-- ---------------------------------------------------------------------------
-- local hunter resolution
--
-- getMasterPlayer() is the quest HOST, not the local hunter (the bug
-- hunt_dumper already fixed once). Walk the instanced player list first and
-- pick the entry the game itself marks user-controlled; fall back to master
-- only when the list yields nobody.
-- ---------------------------------------------------------------------------

-- Array access helper declared before its users (arrays expose get_Item,
-- not always []).
local function array_get_local(arr, i)
    local v = safe(function() return arr[i] end)
    if v == nil then
        local td = safe(function() return arr:get_type_definition() end)
        local m = td and safe(function() return td:get_method("get_Item(System.Int32)") end)
        if m then v = safe(function() return m:call(arr, i) end) end
    end
    return v
end

local function instanced_array(pm)
    local list = field_value(pm, "_InstancedPlayerList")
        or field_value(pm, "<InstancedPlayerList>k__BackingField")
        or field_value(pm, "_PlayerList")
    if not list then return nil end
    return field_value(list, "_Array")
        or field_value(list, "<Array>k__BackingField")
        or field_value(list, "_Items")
        or list
end

local function character_of(inst, pi)
    for _, name in ipairs({ "get_Character", "get_Hunter", "get_Player" }) do
        local v = pi and call_method(pi, name)
        if v ~= nil and v ~= 0 then return v end
    end
    for _, name in ipairs({ "get_Hunter", "get_Character" }) do
        local v = call_method(inst, name)
        if v ~= nil and v ~= 0 then return v end
    end
    return field_value(inst, "<Character>k__BackingField")
        or field_value(inst, "_Character")
end

-- Returns status object + source tag, or nil + reason.
local function local_status()
    local pm = safe(function() return sdk.get_managed_singleton("app.PlayerManager") end)
    if not pm then return nil, "no_player_manager" end

    local arr = instanced_array(pm)
    if arr then
        for i = 0, 7 do
            local inst = array_get_local(arr, i)
            if inst == nil then break end
            local pi = call_method(inst, "get_PlayerInfo")
            local ch = character_of(inst, pi)
            local st = ch and call_method(ch, "get_HunterStatus")
            if st then
                local is_user = call_method(st, "get_IsUserControl")
                local is_npc = call_method(st, "get_IsNpc")
                if is_user == true and is_npc ~= true then
                    return st, "user_control"
                end
            end
        end
    end

    local mp = typecall("app.PlayerManager", "getMasterPlayer", pm)
    local ch = mp and (field_value(mp, "<Character>k__BackingField")
        or call_method(mp, "get_Character"))
    local st = ch and call_method(ch, "get_HunterStatus")
    if st then return st, "master_fallback" end
    return nil, "no_status"
end

-- ---------------------------------------------------------------------------
-- meal access + strip fields
-- ---------------------------------------------------------------------------

local MEAL_TYPE = "app.cHunterMealEffect"

local STRIP_FIELDS = {
    { name = "_IsTimerActive",     value = false },
    { name = "_IsEffectActive",    value = false },
    { name = "_DurationTimer",     value = 0.0 },
    { name = "_MaxHealthAdd",      value = 0.0 },
    { name = "_MaxStaminaAdd",     value = 0.0 },
    { name = "_TempIsTimerActive", value = false },
    { name = "_TempIsEffectActive", value = false },
}

local function meal_object()
    local st, src = local_status()
    if not st then return nil, src end
    local meal = field_value(st, "_MealEffect")
    if not meal then return nil, "no_meal_object" end
    return meal, src
end

-- Capture pre-strip values for Restore, then write the strip set.
local function write_strip(meal)
    saved_values = {}
    for _, sf in ipairs(STRIP_FIELDS) do
        saved_values[sf.name] = field_value(meal, sf.name)
    end
    local okCount, missing = 0, {}
    for _, sf in ipairs(STRIP_FIELDS) do
        -- Read first: set_field() reports success even when the field name is
        -- wrong (it only logs), so existence is decided by the read, not the
        -- write. A field renamed by a game patch becomes a logged miss.
        local current = field_value(meal, sf.name)
        if current == nil then
            missing[#missing + 1] = sf.name
        else
            local ok = write_field(meal, MEAL_TYPE, sf.name, sf.value)
            if ok then okCount = okCount + 1 end
        end
    end
    return okCount, missing
end

local function strip_meal()
    local meal, src = meal_object()
    if not meal then
        lastStatus = "strip: no meal object (" .. tostring(src) .. ")"
        log.warn("[MealStripper] " .. lastStatus)
        return
    end
    local okCount, missing = write_strip(meal)
    strippedAt = os.date("%H:%M:%S")
    lastStatus = string.format("strip: %d/%d fields written @ %s%s",
        okCount, #STRIP_FIELDS, strippedAt,
        #missing > 0 and ("  missing: " .. table.concat(missing, ", ")) or "")
    if #missing > 0 then
        log.warn("[MealStripper] " .. lastStatus)
    else
        log.info("[MealStripper] " .. lastStatus)
    end
end

local function restore_meal()
    if not saved_values then
        lastStatus = "restore: nothing saved (strip first)"
        log.warn("[MealStripper] " .. lastStatus)
        return
    end
    local meal, src = meal_object()
    if not meal then
        lastStatus = "restore: no meal object (" .. tostring(src) .. ")"
        log.warn("[MealStripper] " .. lastStatus)
        return
    end
    -- Restore only replays the 7 tracked fields (flags/timer/HP+stamina adds).
    -- A meal eaten since the strip keeps its food skills and attack/defence
    -- adds; say so instead of implying a full swap.
    local active = field_value(meal, "_IsEffectActive")
    local n = 0
    for name, value in pairs(saved_values) do
        if value ~= nil then
            local ok = write_field(meal, MEAL_TYPE, name, value)
            if ok then n = n + 1 end
        end
    end
    lastStatus = string.format("restore: %d fields written back%s @ %s",
        n,
        active == true and " (a meal is active: tracked fields only, skills untouched)" or "",
        os.date("%H:%M:%S"))
    log.info("[MealStripper] " .. lastStatus)
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local function meal_line()
    local meal, src = meal_object()
    if not meal then return "meal: unavailable (" .. tostring(src) .. ")" end
    return string.format("meal: active=%s  timer=%s  hp=+%s  stam=+%s",
        tostring(field_value(meal, "_IsEffectActive")),
        tostring(field_value(meal, "_DurationTimer")),
        tostring(field_value(meal, "_MaxHealthAdd")),
        tostring(field_value(meal, "_MaxStaminaAdd")))
end

local function draw_ui()
    if not imgui.tree_node("Meal Stripper v" .. VERSION) then return end
    imgui.text("scope: meal buff only")
    imgui.text(meal_line())
    imgui.separator()

    if imgui.button("Strip meal now") then
        local ok, err = pcall(strip_meal)
        if not ok then lastStatus = "strip error: " .. tostring(err) end
    end
    imgui.same_line()
    if imgui.button("Restore last") then
        local ok, err = pcall(restore_meal)
        if not ok then lastStatus = "restore error: " .. tostring(err) end
    end

    imgui.separator()
    imgui.text("status: " .. tostring(lastStatus))
    if strippedAt then
        imgui.text("last strip: " .. strippedAt .. " (restore = 7 tracked fields only)")
    end
    imgui.separator()
    imgui.text("1) eat a meal   2) Strip meal now   3) eat another meal")
    imgui.tree_pop()
end

-- ---------------------------------------------------------------------------

if not ALREADY_LOADED then
    re.on_draw_ui(function()
        local ok, err = pcall(draw_ui)
        if not ok then log.warn("[MealStripper] draw_ui: " .. tostring(err)) end
    end)
    log.info("[MealStripper] loaded v" .. VERSION
        .. " (meal only, no hooks, UI callback only - nothing runs until a button is pressed)")
else
    log.info("[MealStripper] duplicate load ignored (callbacks already registered)")
end
