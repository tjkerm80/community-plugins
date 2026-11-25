-- Host harness for the bar capsule: the active Claude profile as two quota pills.

-- A fixed clock keeps tick positions exact.
local NOW = 1792166400
local realTime, realDate = os.time, os.date
local os = setmetatable({
    date = function(format, time) return realDate(format, time or NOW) end,
    time = function(date)
        if date ~= nil then return realTime(date) end
        return NOW
    end,
}, { __index = os })

local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local function resetIn(seconds) return os.date("!%Y-%m-%dT%H:%M:%SZ", NOW + seconds) end

-- Session resets in 2.5h and weekly in 3.5d, so both windows are half elapsed.
local function profile(label, session, weekly)
    local metrics = {
        { type = "metric", label = "Fable (7d)", percent = 100, value = "100%", window_secs = 604800,
          reset_at = resetIn(3600) },
        { type = "metric", label = "Weekly (7d)", percent = weekly, value = weekly .. "%", window_secs = 604800,
          reset_at = resetIn(302400) },
    }
    if session ~= nil then
        table.insert(metrics, 1, { type = "metric", label = "Session (5h)", percent = session,
            value = session .. "%", window_secs = 18000, reset_at = resetIn(9000) })
    end
    local id = label and ("anthropic@" .. label) or "anthropic"
    return { id = id, display_name = label and ("Claude · " .. label) or "Claude", status = "ready",
        metrics = metrics, sections = metrics }
end

local function loadBar(config, report, failure, activeAccount)
    local values = {
        report = report,
        error = failure or { code = "", detail = "" },
        active_account = activeAccount,
    }
    local rendered, tooltip, toggled
    local watchers = {}
    local noctalia = {
        getConfig = function(key) return config[key] end,
        state = {
            get = function(key) return values[key] end,
            set = function(key, value) values[key] = value end,
            watch = function(key, callback) watchers[key] = callback end,
        },
        setUpdateInterval = function() end,
        togglePanel = function(id) toggled = id end,
        tr = function(key, args)
            if type(args) ~= "table" then return key end
            local parts = { key }
            for _, name in ipairs({ "percent", "time", "window" }) do
                if args[name] ~= nil then parts[#parts + 1] = tostring(args[name]) end
            end
            return table.concat(parts, " ")
        end,
        formatTime = function(_, at) return os.date("!%H:%M", at) end,
        timeFormat = function() return "HH:mm" end,
        string = {
            trim = function(value) return tostring(value):match("^%s*(.-)%s*$") end,
        },
    }
    local ui = setmetatable({}, {
        __index = function(_, kind)
            return function(props, children)
                return { kind = kind, props = props or {}, children = children or {} }
            end
        end,
    })
    local barWidget = {
        render = function(node) rendered = node end,
        setTooltip = function(rows) tooltip = rows end,
        isVertical = function() return config.vertical == true end,
    }
    local sharedEnv = setmetatable({ noctalia = noctalia, os = os }, { __index = _G })
    local shared = assert(load(read("shared.luau"), "shared", "t", sharedEnv))()
    local env = setmetatable({
        noctalia = noctalia,
        ui = ui,
        barWidget = barWidget,
        require = function(path)
            assert(path == "./shared.luau")
            return shared
        end,
    }, { __index = _G })
    assert(load(read("bar.luau"), "bar", "t", env))()
    return {
        env = env,
        values = values,
        rendered = function() return rendered end,
        tooltip = function() return tooltip end,
        toggled = function() return toggled end,
        publish = function(key, value)
            values[key] = value
            watchers[key](value)
        end,
    }
end

local function collect(node, kind, found)
    found = found or {}
    if type(node) ~= "table" then return found end
    if node.kind == kind then found[#found + 1] = node end
    for _, child in ipairs(node.children or {}) do collect(child, kind, found) end
    return found
end

local function keyed(node, key)
    if type(node) ~= "table" then return nil end
    if type(node.props) == "table" and node.props.key == key then return node end
    for _, child in ipairs(node.children or {}) do
        local found = keyed(child, key)
        if found ~= nil then return found end
    end
    return nil
end

local function tooltipValue(bar, key)
    for _, row in ipairs(bar.tooltip() or {}) do
        if row.key == key then return row.value end
    end
    return nil
end

-- The pill's first child; its segments are the boxes before the trailing spacer.
local function segments(window)
    local pill = window.children[1]
    local out = {}
    for _, child in ipairs(pill.children) do
        if child.kind == "box" then out[#out + 1] = { child.props.key:match("^(%a+)"), child.props.width, child.props.fill } end
    end
    return pill, out
end

local function describe(list)
    local parts = {}
    for _, segment in ipairs(list) do parts[#parts + 1] = segment[1] .. ":" .. segment[2] end
    return table.concat(parts, ",")
end

local report = { entries = {
    profile(nil, 90, 90),
    profile("work", 30, 80),
    profile("personal", nil, 10),
} }

-- The active profile is drawn; the bare login is the fallback when no label matches.
do
    local bar = loadBar({}, report, nil, "work")
    assert(tooltipValue(bar, "ui.account") == "Claude · work", "the bar must show the active profile")
    local session, weekly = keyed(bar.rendered(), "session"), keyed(bar.rendered(), "weekly")
    assert(session and weekly and session.kind == "row", "both windows sit side by side in a horizontal bar")

    -- 30% of 36px is 11px of fill; the tick sits at half the width, 17px in.
    local pill, parts = segments(session)
    assert(pill.props.width == 36 and pill.props.fill == "on_surface/0.14", "the pill is a 36px track")
    assert(describe(parts) == "fill:11,track:6,tick:2", "usage behind time leaves a track gap before the tick; got "
        .. describe(parts))
    assert(parts[1][3] == "primary" and parts[3][3] == "on_surface", "usage behind time keeps the primary fill")
    assert(keyed(session, "session-percent").props.text == "30%", "each pill carries its percentage")

    -- 80% weekly is ahead of the half-elapsed window, so the fill crosses the tick.
    local _, weeklyParts = segments(weekly)
    assert(describe(weeklyParts) == "fill:17,tick:2,fill:10", "usage ahead of time fills past the tick; got "
        .. describe(weeklyParts))
    assert(weeklyParts[1][3] == "secondary" and weeklyParts[3][3] == "secondary",
        "usage ahead of time turns the fill to the warning colour")
    assert(keyed(weekly, "weekly-percent").props.text == "80%",
        "the weekly pill reads the overall Weekly quota, not the Fable pool")

    assert(tooltipValue(bar, "ui.session 5h") == "ui.tooltip_used 30% · ui.tooltip_elapsed 50",
        "the tooltip gives each window's usage and elapsed time in one short value; got "
        .. tostring(tooltipValue(bar, "ui.session 5h")))
    assert(tooltipValue(bar, "ui.tooltip_resets ui.session 5h") == "2h 30m · 18:30",
        "each window's reset gets its own row with the countdown and clock time; got "
        .. tostring(tooltipValue(bar, "ui.tooltip_resets ui.session 5h")))
    assert(tooltipValue(bar, "ui.weekly 7d"):find("80%", 1, true), "the tooltip lists the weekly window")
    for _, row in ipairs(bar.tooltip()) do
        assert(row.value ~= "ui.tooltip_more", "the tooltip drops the click hint")
    end

    bar.publish("active_account", "missing")
    assert(tooltipValue(bar, "ui.account") == "Claude", "an unknown label falls back to the bare login")
    bar.publish("active_account", "work")
    assert(tooltipValue(bar, "ui.account") == "Claude · work", "a new active label redraws the bar")

    bar.env.onClick()
    assert(bar.values.selected == "anthropic@work" and bar.values.bar_detail == false
        and bar.toggled() == "felipeartur/ai-usagebar:panel", "a click opens the overview at the active profile")
end

-- A profile without a 5-hour window has no such limit; a hollow pill says so.
do
    local bar = loadBar({}, report, nil, "personal")
    local session = keyed(bar.rendered(), "session")
    local pill, parts = segments(session)
    assert(#parts == 0 and pill.props.fill == nil and pill.props.border ~= nil and pill.props.borderWidth == 1,
        "no 5-hour limit draws an outline with no fill and no tick")
    assert(keyed(session, "session-percent").props.text == "∞", "no 5-hour limit reads as unlimited, not 0%")
    assert(tooltipValue(bar, "ui.session 5h") == "ui.no_limit", "the tooltip names the missing limit")
    assert(tooltipValue(bar, "ui.tooltip_resets ui.session 5h") == nil, "a missing limit has no reset row")
    assert(keyed(bar.rendered(), "weekly-percent").props.text == "10%", "the weekly pill is unaffected")
end

-- A real 0% keeps the solid track and its tick.
do
    local bar = loadBar({}, { entries = { profile("idle", 0, 0) } }, nil, "idle")
    local pill, parts = segments(keyed(bar.rendered(), "session"))
    assert(pill.props.fill == "on_surface/0.14" and describe(parts) == "track:17,tick:2",
        "0% of a real limit is an empty track with a tick")
    assert(keyed(bar.rendered(), "session-percent").props.text == "0%", "0% of a real limit reads 0%")
end

-- Remaining mode changes the labels only.
do
    local bar = loadBar({ usage_display = "remaining" }, report, nil, "work")
    assert(keyed(bar.rendered(), "session-percent").props.text == "70%", "remaining mode inverts the label")
    local _, parts = segments(keyed(bar.rendered(), "session"))
    assert(describe(parts) == "fill:11,track:6,tick:2", "remaining mode keeps the pill measuring usage")
end

-- A vertical bar stacks each pill above its label.
do
    local bar = loadBar({ vertical = true }, report, nil, "work")
    local session = keyed(bar.rendered(), "session")
    assert(session.kind == "column" and session.children[1].props.width == 22, "vertical bars use narrow pills")
end

-- Failures colour the glyph and keep the last numbers.
do
    local failure = { code = "timed_out", detail = "" }
    local bar = loadBar({}, report, failure, "work")
    local glyph = collect(bar.rendered(), "glyph")[1]
    assert(glyph.props.color == "error", "a failed read colours the provider glyph")
    assert(keyed(bar.rendered(), "session-percent").props.text == "30%", "a failed read keeps the last numbers")
    assert(tooltipValue(bar, "ui.title") == "ui.error.timed_out", "the failure leads the tooltip")

    local empty = loadBar({}, nil, failure, "")
    local brain = collect(empty.rendered(), "glyph")[1]
    assert(brain.props.name == "brain" and brain.props.color == "error", "no report and a failure shows an error glyph")

    local waiting = loadBar({ show_glyph = false }, nil, nil, nil)
    assert(collect(waiting.rendered(), "glyph")[1].props.color == "on_surface_variant"
        and tooltipValue(waiting, "ui.title") == "ui.waiting", "before the first read the bar waits")

    local hidden = loadBar({ show_glyph = false }, report, nil, "work")
    assert(#collect(hidden.rendered(), "glyph") == 0, "show_glyph = false drops the provider glyph")
end

io.write("ok: bar draws the active profile's 5h and weekly pills with elapsed ticks\n")
