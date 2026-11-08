--
-- MealProbe v1 — dev probe for a "strip the meal so you can eat again" mod
--
-- Goal (speedrunning): clear the ACTIVE meal so the canteen lets you eat a
-- different one. This probe answers three questions on this game build:
--   1. what state does a meal actually live in (fields + methods),
--   2. does zeroing it stick, or does the game rewrite it every tick,
--   3. does the game's own "meal is active" check flip to false.
--
-- Load: sits in reframework\autorun\ with the other scripts, so it appears in
--   "Script Generated UI" at startup and after Reset scripts. It registers a
--   menu node and two quest-state hooks at load and then does NOTHING until a
--   button is pressed: no load-time dumping, no per-frame work.
--   Reload: REFramework menu -> "Script" -> "Reset scripts" (or restart the
--   game). Reset recreates the Lua state, so the duplicate-load guard below
--   never blocks a legitimate reload.
--
-- Buttons:
--   Dump types   -> reframework/data/meal_probe_types.json
--   Snapshot     -> reframework/data/meal_probe_state.json
--   Strip meal   -> writes the strip fields, re-reads at +15 and +120 frames
--                   -> reframework/data/meal_probe_strip.json
--   Restore      -> writes the pre-strip values of the last strip back
--
-- Every SDK call is pcall-guarded: this script never throws into the game.
--

local re = re
local sdk = sdk
local json = json
local log = log
local imgui = imgui

local PROBE_VERSION = 1
local OUT_TYPES = "meal_probe_types.json"
local OUT_STATE = "meal_probe_state.json"
local OUT_STRIP = "meal_probe_strip.json"

-- Re-running the script must not register a second set of callbacks/hooks.
local ALREADY_LOADED = _G.MEAL_PROBE_LOADED == true
_G.MEAL_PROBE_LOADED = true

local lastStatus = "(idle)"

-- ---------------------------------------------------------------------------
-- small helpers (same shapes hunt_dumper already proves on this build)
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

local function collect(list, maxItems)
    local out = {}
    if list == nil then return out end
    local cnt = safe(function() return list.get_Count end)
    local item = safe(function() return list.get_Item end)
    if cnt ~= nil and item ~= nil then
        local n = safe(function() return cnt:call(list) end) or 0
        if maxItems and n > maxItems then n = maxItems end
        for i = 0, n - 1 do
            out[#out + 1] = safe(function() return item:call(list, i) end)
        end
        return out
    end
    for i = 0, 64 do
        if maxItems and i >= maxItems then break end
        local v = safe(function() return list[i] end)
        if v == nil then break end
        out[#out + 1] = v
    end
    return out
end

local function array_get(arr, i)
    local v = safe(function() return arr[i] end)
    if v == nil then
        local td = safe(function() return arr:get_type_definition() end)
        local m = td and safe(function() return td:get_method("get_Item(System.Int32)") end)
        if m then v = safe(function() return m:call(arr, i) end) end
    end
    return v
end

-- ---------------------------------------------------------------------------
-- type dumps — fields + full signatures, so method NAMES for a clean removal
-- (clearMeal / endMeal / ...) or for the re-eat gate show up in one click
-- ---------------------------------------------------------------------------

local PRIMITIVE = {
    Boolean = true, Single = true, Double = true, Int32 = true, UInt32 = true,
    Int16 = true, UInt16 = true, Byte = true, SByte = true, Int64 = true,
    UInt64 = true, String = true,
}

local function describe_field(f)
    return {
        name = safe(function() return f:get_name() end),
        type = safe(function() return f:get_type():get_name() end),
        static = safe(function() return f:is_static() end),
    }
end

local function describe_method(m)
    local params = {}
    local n = safe(function() return m:get_num_params() end) or 0
    local pts = safe(function() return m:get_param_types() end) or {}
    for i = 1, n do
        local t = pts[i]
        params[#params + 1] = safe_str(safe(function() return t:get_name() end)) or "?"
    end
    return {
        name = safe(function() return m:get_name() end),
        full = safe(function() return m:get_full_name() end),
        ret = safe(function() return m:get_return_type():get_name() end),
        params = params,
    }
end

local function dump_type(typeName)
    local td = safe(sdk.find_type_definition, typeName)
    local entry = { name = typeName, exists = td ~= nil }
    if not td then return entry end
    entry.full_name = safe(function() return td:get_full_name() end)

    local fields = safe(function() return td:get_fields() end)
    if fields then
        entry.fields = {}
        for _, f in ipairs(fields) do
            entry.fields[#entry.fields + 1] = describe_field(f)
        end
    end

    local methods = safe(function() return td:get_methods() end)
    if methods then
        entry.methods = {}
        for _, m in ipairs(methods) do
            entry.methods[#entry.methods + 1] = describe_method(m)
        end
    end
    return entry
end

-- The meal surface we already know, plus candidates for the thing that blocks
-- re-eating (facility/dining/canteen GUI). Candidates that do not exist are
-- kept in the dump with exists=false so the misses are recorded too.
local MEAL_TYPES = {
    -- known meal / buff containers
    "app.cHunterStatus", "app.cHunterMealEffect", "app.cMealEffect",
    "app.cHunterMealSkillParamInfo", "app.cHunterItemBuff",
    "app.cHunterAttackPower", "app.cHunterDefencePower", "app.cHunterCritical",
    "app.cHunterHealth", "app.cHunterStamina", "app.cHunterEffect",
    "app.HunterCharacter", "app.cPlayerManageInfo", "app.PlayerManager",
    -- quest state (holds isMealEffectActive)
    "app.cQuestPlaying", "app.cQuestDirector", "app.cQuestFlowParam",
    -- meal definition / apply path
    "app.MealDef", "app.MealUtil", "app.cMealUtil", "app.MealManager",
    "app.cMealManager", "app.user_data.MealSkillData.cData",
    "app.user_data.MealSkillRandomTable.cData", "app.MessageUtil",
    -- re-eat gate candidates (facility / dining / canteen)
    "app.FacilityManager", "app.cFacilityManager", "app.cFacilityDining",
    "app.FacilityDiningManager", "app.cFacilityDiningManager",
    "app.DiningManager", "app.cDiningManager", "app.DiningDef",
    "app.RestaurantManager", "app.cRestaurantManager", "app.GuiRestaurant",
    "app.cGuiRestaurant", "app.GuiDining", "app.cGuiDining",
    "app.GuiCanteen", "app.cGuiCanteen", "app.CanteenManager",
    "app.cCanteenManager", "app.CanteenDef", "app.cCanteenDef",
    "app.GuiMeal", "app.cGuiMeal", "app.CampDiningManager",
    "app.cCampDiningManager", "app.CampManager", "app.cCampManager",
    "app.CampUtil", "app.FacilityDef", "app.cFacilityDef",
    "app.user_data.FacilityDiningSetting", "app.user_data.FacilitySetting",
}

local function dump_types()
    local out = { probe_version = PROBE_VERSION, kinds = {} }
    for _, name in ipairs(MEAL_TYPES) do
        out.kinds[#out.kinds + 1] = dump_type(name)
    end
    json.dump_file(OUT_TYPES, out)
    local n, hits = 0, {}
    for _, e in ipairs(out.kinds) do
        if e.exists then
            n = n + 1
            hits[#hits + 1] = e.name
        end
    end
    lastStatus = string.format("types: %d/%d exist -> %s", n, #MEAL_TYPES, OUT_TYPES)
    log.info("[MealProbe] " .. lastStatus)
    log.info("[MealProbe] existing: " .. table.concat(hits, ", "))
    return out
end

-- ---------------------------------------------------------------------------
-- local hunter resolution
--
-- getMasterPlayer() is the quest HOST, not the local hunter (the bug hunt_
-- dumper already fixed once). Walk the instanced player list first and pick
-- the entry the game itself marks user-controlled; fall back to master only
-- when the list yields nobody, and say so in the dump.
-- ---------------------------------------------------------------------------

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

-- Returns { status, char, src, candidates = {...} } or nil.
local function local_status()
    local pm = safe(function() return sdk.get_managed_singleton("app.PlayerManager") end)
    if not pm then return nil end

    local out = { candidates = {} }
    local arr = instanced_array(pm)
    if arr then
        for i = 0, 7 do
            local inst = array_get(arr, i)
            if inst == nil then break end
            local pi = call_method(inst, "get_PlayerInfo")
            local ch = character_of(inst, pi)
            local st = ch and call_method(ch, "get_HunterStatus")
            if st then
                local rec = {
                    slot = i,
                    is_master = call_method(st, "get_IsMaster"),
                    is_npc = call_method(st, "get_IsNpc"),
                    is_user_control = call_method(st, "get_IsUserControl"),
                    type = safe_str(safe(function()
                        local t = st:get_type_definition()
                        return t and t:get_full_name()
                    end)),
                }
                out.candidates[#out.candidates + 1] = rec
                if rec.is_user_control == true and rec.is_npc ~= true and not out.status then
                    out.status, out.char, out.src = st, ch, "user_control"
                end
            end
        end
    end

    if not out.status then
        local mp = typecall("app.PlayerManager", "getMasterPlayer", pm)
        local ch = mp and (field_value(mp, "<Character>k__BackingField")
            or call_method(mp, "get_Character"))
        local st = ch and call_method(ch, "get_HunterStatus")
        if st then
            out.status, out.char = st, ch
            out.src = "master_fallback"
        else
            out.fail = "no_status"
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- snapshots
-- ---------------------------------------------------------------------------

-- Every primitive field + every 0-arg primitive getter of an object. Primitives
-- only: no getter that returns an object is called, so nothing new is allocated
-- and there is nothing to leak or dangle.
local function object_snapshot(obj, label)
    local snap = { label = label }
    if obj == nil then
        snap.fail = "nil"
        return snap
    end
    local td = safe(function() return obj:get_type_definition() end)
    snap.type = safe_str(safe(function() return td and td:get_full_name() end))

    for _, f in ipairs(safe(function() return td and td:get_fields() end) or {}) do
        local fname = safe(function() return f:get_name() end)
        local ftype = safe_str(safe(function() return f:get_type():get_name() end))
        if fname and PRIMITIVE[ftype] then
            snap[fname] = safe_str(safe(function()
                local is_static = safe(function() return f:is_static() end)
                return f:get_data(is_static and nil or obj)
            end))
        end
    end

    for _, m in ipairs(safe(function() return td and td:get_methods() end) or {}) do
        local mname = safe(function() return m:get_name() end) or ""
        local nparams = safe(function() return m:get_num_params() end) or 0
        local ret = safe_str(safe(function() return m:get_return_type():get_name() end))
        if mname:find("^get_") and nparams == 0 and ret and PRIMITIVE[ret] then
            local v = safe(function() return m:call(obj) end)
            if v ~= nil then snap[mname] = safe_str(v) end
        end
    end
    return snap
end

-- The stats a meal moves: attack/defence/crit boxes, health and stamina max.
local function stats_snapshot(st)
    local out = {}
    if st == nil then return out end
    local ap = call_method(st, "get_AttackPower")
    if ap then out.attack = object_snapshot(ap, "attack") end
    local dp = call_method(st, "get_DefencePower")
    if dp then out.defence = object_snapshot(dp, "defence") end
    local cr = call_method(st, "get_CriticalRate")
    if cr then out.critical = object_snapshot(cr, "critical") end
    local hp = call_method(st, "get_Health") or field_value(st, "_Health")
    if hp then out.health = object_snapshot(hp, "health") end
    local sp = call_method(st, "get_Stamina") or field_value(st, "_Stamina")
    if sp then out.stamina = object_snapshot(sp, "stamina") end
    return out
end

-- cQuestPlaying.isMealEffectActive() — the game's own "you have a meal" check.
-- The instance is captured from the update() hook below (it is not exposed as
-- a singleton we can reach any other way).
local quest_state = nil

local function gate_snapshot()
    local out = { available = false }
    if quest_state == nil then
        out.reason = "no_quest_state"
        return out
    end
    -- The pointer came from a hook; never call through it if the runtime says
    -- it is not a live managed object any more.
    if sdk.is_managed_object ~= nil and not safe(sdk.is_managed_object, quest_state) then
        quest_state = nil
        out.reason = "stale"
        return out
    end
    out.available = true
    local v = safe(function() return quest_state:call("isMealEffectActive") end)
    out.isMealEffectActive = safe_str(v)
    return out
end

-- Full state: local hunter + meal object + stats + gate.
local function state_snapshot()
    local res = local_status()
    local out = { probe_version = PROBE_VERSION, wall = os.date("!%Y-%m-%dT%H:%M:%SZ") }
    if not res or not res.status then
        out.fail = res and res.fail or "no_player_manager"
        out.candidates = res and res.candidates or nil
        json.dump_file(OUT_STATE, out)
        lastStatus = "state: no local status (" .. tostring(out.fail) .. ")"
        log.warn("[MealProbe] " .. lastStatus)
        return out
    end

    out.src = res.src
    out.candidates = res.candidates
    local st = res.status
    out.is_master = call_method(st, "get_IsMaster")
    out.is_npc = call_method(st, "get_IsNpc")
    out.is_user_control = call_method(st, "get_IsUserControl")

    local meal = field_value(st, "_MealEffect")
    out.meal = object_snapshot(meal, "meal")
    local inner = meal and field_value(meal, "_MealEffect")
    out.meal_inner = object_snapshot(inner, "meal_inner")
    out.stats = stats_snapshot(st)
    out.gate = gate_snapshot()

    json.dump_file(OUT_STATE, out)
    lastStatus = string.format("state: src=%s timer=%s active=%s gate=%s -> %s",
        tostring(out.src),
        tostring(out.meal and out.meal._DurationTimer),
        tostring(out.meal and out.meal._IsEffectActive),
        tostring(out.gate.isMealEffectActive),
        OUT_STATE)
    log.info("[MealProbe] " .. lastStatus)
    return out
end

-- ---------------------------------------------------------------------------
-- strip / restore
--
-- Fields taken from the cHunterMealEffect dump; each one is only written when
-- it exists on this build, so a field rename degrades to a logged miss instead
-- of an error. Values are kept so "Restore" can put the meal back (which is
-- also how we prove the stat change came from the meal and not from timing).
-- ---------------------------------------------------------------------------

local STRIP_FIELDS = {
    { name = "_IsTimerActive",     value = false },
    { name = "_IsEffectActive",    value = false },
    { name = "_DurationTimer",     value = 0.0 },
    { name = "_MaxHealthAdd",      value = 0.0 },
    { name = "_MaxStaminaAdd",     value = 0.0 },
    { name = "_TempIsTimerActive", value = false },
    { name = "_TempIsEffectActive", value = false },
}

local MEAL_TYPE = "app.cHunterMealEffect"
local saved_values = nil      -- field -> pre-strip value, for Restore
local pending_verify = nil    -- { frames = {15, 120}, done = {}, readings = {} }

local function meal_object()
    local res = local_status()
    if not res or not res.status then return nil, "no_status" end
    local meal = field_value(res.status, "_MealEffect")
    if not meal then return nil, "no_meal_object" end
    return meal, res.src
end

local function reading(tag)
    local meal, src = meal_object()
    local res = local_status()
    local r = { tag = tag, src = src }
    if meal then
        r.fields = {}
        for _, sf in ipairs(STRIP_FIELDS) do
            r.fields[sf.name] = safe_str(field_value(meal, sf.name))
        end
    else
        r.fail = src
    end
    if res and res.status then
        r.stats = stats_snapshot(res.status)
    end
    r.gate = gate_snapshot()
    return r
end

local function strip_meal()
    local meal, src = meal_object()
    if not meal then
        lastStatus = "strip: " .. tostring(src)
        log.warn("[MealProbe] " .. lastStatus)
        return nil
    end

    -- capture pre-strip values for Restore
    saved_values = {}
    for _, sf in ipairs(STRIP_FIELDS) do
        saved_values[sf.name] = field_value(meal, sf.name)
    end

    local out = {
        probe_version = PROBE_VERSION,
        src = src,
        wall = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        before = reading("before"),
        writes = {},
    }

    for _, sf in ipairs(STRIP_FIELDS) do
        -- Read first: set_field() reports success even when the field name is
        -- wrong (it only logs), so existence is decided by the read, not the
        -- write. A field renamed by a game patch becomes a logged miss.
        local current = field_value(meal, sf.name)
        local rec = {
            field = sf.name,
            wanted = safe_str(sf.value),
            exists = current ~= nil,
            before = safe_str(current),
        }
        if not rec.exists then
            rec.ok, rec.via = false, "field_missing"
        else
            local ok, how = write_field(meal, MEAL_TYPE, sf.name, sf.value)
            rec.ok, rec.via = ok, how
        end
        out.writes[#out.writes + 1] = rec
        log.info(string.format("[MealProbe] write %s = %s -> %s (%s)",
            sf.name, tostring(sf.value), tostring(rec.ok), tostring(rec.via)))
    end

    out.after_immediate = reading("after_immediate")
    json.dump_file(OUT_STRIP, out)

    -- The game may rewrite these every tick; re-read later to find out.
    pending_verify = { frames = { 15, 120 }, done = {}, readings = {} }

    lastStatus = string.format("strip: %d writes, verifying at +15/+120 frames",
        #out.writes)
    log.info("[MealProbe] " .. lastStatus)
    return out
end

local function restore_meal()
    if not saved_values then
        lastStatus = "restore: nothing saved (strip first)"
        log.warn("[MealProbe] " .. lastStatus)
        return
    end
    local meal, src = meal_object()
    if not meal then
        lastStatus = "restore: " .. tostring(src)
        log.warn("[MealProbe] " .. lastStatus)
        return
    end
    local n = 0
    for name, value in pairs(saved_values) do
        if value ~= nil then
            local ok = write_field(meal, MEAL_TYPE, name, value)
            if ok then n = n + 1 end
        end
    end
    lastStatus = string.format("restore: %d fields written back", n)
    log.info("[MealProbe] " .. lastStatus)
end

-- ---------------------------------------------------------------------------
-- callbacks
-- ---------------------------------------------------------------------------

local function on_frame()
    if pending_verify == nil then return end
    pending_verify.count = (pending_verify.count or 0) + 1
    for i, target in ipairs(pending_verify.frames) do
        if not pending_verify.done[i] and pending_verify.count >= target then
            pending_verify.done[i] = true
            local r = reading("after_" .. target .. "f")
            pending_verify.readings[#pending_verify.readings + 1] = r
            log.info(string.format(
                "[MealProbe] verify +%df: timer=%s effect=%s gate=%s",
                target,
                tostring(r.fields and r.fields._DurationTimer),
                tostring(r.fields and r.fields._IsEffectActive),
                tostring(r.gate and r.gate.isMealEffectActive)))
        end
    end
    if #pending_verify.done >= #pending_verify.frames then
        local out = json.load_file(OUT_STRIP) or {}
        out.verify = pending_verify.readings
        json.dump_file(OUT_STRIP, out)
        lastStatus = "strip: verify written -> " .. OUT_STRIP
        log.info("[MealProbe] " .. lastStatus)
        pending_verify = nil
    end
end

local function register_hooks()
    -- Capture the cQuestPlaying instance so isMealEffectActive() can be called
    -- on demand. update() runs every frame while a quest is live; exit() drops
    -- the pointer so it is never used after the state is torn down.
    local hooked = {}
    safe(function()
        local t = sdk.find_type_definition("app.cQuestPlaying")
        if not t then
            log.warn("[MealProbe] app.cQuestPlaying not found; gate check unavailable")
            return
        end
        local m = t:get_method("update()")
        if m then
            sdk.hook(m, function(args)
                quest_state = sdk.to_managed_object(args[2])
            end, nil)
            hooked[#hooked + 1] = "update"
        end
        local mx = t:get_method("exit()")
        if mx then
            sdk.hook(mx, function() quest_state = nil end, nil)
            hooked[#hooked + 1] = "exit"
        end
    end)
    if #hooked == 0 then
        log.warn("[MealProbe] no cQuestPlaying hooks registered (gate check unavailable)")
    else
        log.info("[MealProbe] hooks: cQuestPlaying." .. table.concat(hooked, ", "))
    end
end

-- ---------------------------------------------------------------------------
-- UI
-- ---------------------------------------------------------------------------

local function draw_ui()
    if not imgui.tree_node("MealProbe (strip meal)") then return end
    imgui.text("v" .. tostring(PROBE_VERSION) .. "  dev probe - autorun, buttons only")
    imgui.text("Writes JSON to reframework/data/")
    imgui.separator()

    if imgui.button("Dump types") then
        local ok, err = pcall(dump_types)
        if not ok then lastStatus = "dump_types error: " .. tostring(err) end
    end
    imgui.same_line()
    if imgui.button("Snapshot state") then
        local ok, err = pcall(state_snapshot)
        if not ok then lastStatus = "snapshot error: " .. tostring(err) end
    end

    if imgui.button("Strip meal now") then
        local ok, err = pcall(strip_meal)
        if not ok then lastStatus = "strip error: " .. tostring(err) end
    end
    imgui.same_line()
    if imgui.button("Restore last meal") then
        local ok, err = pcall(restore_meal)
        if not ok then lastStatus = "restore error: " .. tostring(err) end
    end

    imgui.separator()
    imgui.text("status: " .. tostring(lastStatus))
    if pending_verify then
        imgui.text(string.format("verifying: frame %d / %d",
            pending_verify.count or 0,
            pending_verify.frames[#pending_verify.frames]))
    end
    imgui.text("quest state: " .. (quest_state and "captured" or "not in quest"))
    imgui.separator()
    imgui.text("1) eat a meal, 2) Strip meal now, 3) try to eat another meal.")
    imgui.text("4) Snapshot / re-read strip json to see what stuck.")
    imgui.tree_pop()
end

-- ---------------------------------------------------------------------------

if not ALREADY_LOADED then
    re.on_frame(function()
        local ok, err = pcall(on_frame)
        if not ok then log.warn("[MealProbe] on_frame: " .. tostring(err)) end
    end)
    re.on_draw_ui(function()
        local ok, err = pcall(draw_ui)
        if not ok then log.warn("[MealProbe] draw_ui: " .. tostring(err)) end
    end)
    register_hooks()
    log.info("[MealProbe] loaded v" .. tostring(PROBE_VERSION)
        .. " (dev probe, nothing runs until a button is pressed)")
else
    log.info("[MealProbe] duplicate load ignored (callbacks already registered)")
end
