--!nonstrict
-- Bar capsule. Draws the active Claude account as two pills, the 5-hour session
-- and the overall weekly quota, each with its percentage. A window the account
-- has no limit for draws as a hollow pill marked "∞". A tick on each pill
-- marks how far through the window we are, and the fill turns the warning colour
-- when usage is ahead of it. The poller publishes the report and the active
-- account label; this file only draws them.

local showGlyph = noctalia.getConfig("show_glyph") ~= false
local usageDisplay = tostring(noctalia.getConfig("usage_display") or "used")
if usageDisplay ~= "remaining" then usageDisplay = "used" end

local shared = require("./shared.luau")
local NO_FAILURE, asFailure = shared.NO_FAILURE, shared.asFailure

local report = nil
local activeLabel = ""
local failure = NO_FAILURE

local WINDOWS = {
    { id = "session", tag = "5h", title = "ui.session" },
    { id = "weekly", tag = "7d", title = "ui.weekly" },
}

-- ── Tooltip ───────────────────────────────────────────────────────────────────

-- Short values: the tooltip's value column truncates long text.
local function windowSummary(gauge)
    if gauge.metric == nil then return noctalia.tr("ui.no_limit") end
    local percent = shared.gaugeText(gauge, usageDisplay)
    local parts = { noctalia.tr(usageDisplay == "remaining" and "ui.tooltip_left" or "ui.tooltip_used",
        { percent = percent }) }
    if gauge.elapsed ~= nil then
        parts[#parts + 1] = noctalia.tr("ui.tooltip_elapsed", { percent = math.floor(gauge.elapsed + 0.5) })
    end
    return table.concat(parts, " · ")
end

-- "2h 30m · 14:20": the countdown, then the clock time it lands on.
local function resetSummary(gauge)
    if gauge.metric == nil then return "" end
    local countdown = shared.resetDescription(gauge.metric, true)
    if countdown == "" then return "" end
    local clock = shared.resetClock(gauge.metric)
    return clock ~= "" and (countdown .. " · " .. clock) or countdown
end

local function tooltip(entry, gauges)
    local rows = {}
    if failure.code ~= "" then
        rows[#rows + 1] = { key = noctalia.tr("ui.title"), value = noctalia.tr("ui.error." .. failure.code) }
    end
    if entry == nil then
        if failure.code == "" then
            rows[#rows + 1] = { key = noctalia.tr("ui.title"), value = noctalia.tr("ui.waiting") }
        end
    else
        local name = tostring(entry.display_name or entry.id)
        if shared.unavailable(entry) then
            rows[#rows + 1] = { key = name, value = noctalia.tr("ui.unavailable") }
        else
            rows[#rows + 1] = { key = noctalia.tr("ui.account"), value = name }
            for index, window in ipairs(WINDOWS) do
                local title = noctalia.tr(window.title) .. " " .. window.tag
                rows[#rows + 1] = { key = title, value = windowSummary(gauges[index]) }
                local reset = resetSummary(gauges[index])
                if reset ~= "" then
                    rows[#rows + 1] = { key = noctalia.tr("ui.tooltip_resets", { window = title }), value = reset }
                end
            end
            if entry.stale == true then
                rows[#rows + 1] = { key = noctalia.tr("ui.tooltip_data"), value = noctalia.tr("ui.stale_hint") }
            end
        end
    end
    for _, row in ipairs(rows) do
        row.key = noctalia.string.trim((tostring(row.key):gsub("%s+", " ")))
        row.value = noctalia.string.trim((tostring(row.value):gsub("%s+", " ")))
    end
    return rows
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

local function activeEntry() return shared.activeProfile(report, activeLabel) end

local function render()
    local isVertical = type(barWidget.isVertical) == "function" and barWidget.isVertical() or false
    local entry = activeEntry()
    local gauges = {}
    for index, window in ipairs(WINDOWS) do gauges[index] = shared.windowGauge(entry, window.id) end

    local children = {}
    if entry == nil then
        children[1] = ui.glyph({ name = "brain", color = failure.code ~= "" and "error" or "on_surface_variant" })
    else
        -- A failed read keeps the last numbers and colours the glyph instead.
        if showGlyph then
            children[#children + 1] = ui.glyph({
                name = shared.providerGlyph(entry.id, entry.brand), size = 16, width = 18, height = 18,
                color = (failure.code ~= "" or shared.unavailable(entry)) and "error" or "on_surface",
            })
        end
        for index, window in ipairs(WINDOWS) do
            local gauge = gauges[index]
            local label = ui.label({ key = window.id .. "-percent", text = shared.gaugeText(gauge, usageDisplay),
                fontSize = isVertical and 9 or 11, color = "on_surface", maxLines = 1 })
            local reading = { shared.quotaPill(ui, gauge, isVertical and 22 or 36), label }
            children[#children + 1] = isVertical
                and ui.column({ key = window.id, gap = 2, align = "center" }, reading)
                or ui.row({ key = window.id, gap = 4, align = "center" }, reading)
        end
        if entry.stale == true then
            children[#children + 1] = ui.glyph({ name = "clock-exclamation", size = 11, color = "secondary" })
        end
    end

    local layout = { gap = isVertical and 5 or 8, align = "center" }
    barWidget.render(isVertical and ui.column(layout, children) or ui.row(layout, children))
    barWidget.setTooltip(tooltip(entry, gauges))
end

-- ── Wiring ────────────────────────────────────────────────────────────────────

noctalia.state.watch("report", function(value)
    if type(value) == "table" then
        report = value
        failure = NO_FAILURE
        render()
    end
end)

noctalia.state.watch("error", function(value)
    failure = asFailure(value)
    render()
end)

noctalia.state.watch("active_account", function(value)
    activeLabel = type(value) == "string" and value or ""
    render()
end)

function onClick()
    local entry = activeEntry()
    noctalia.state.set("selected", entry ~= nil and entry.id or nil)
    noctalia.state.set("bar_model", nil)
    noctalia.state.set("bar_detail", noctalia.getConfig("panel_view") == "provider" and entry ~= nil)
    noctalia.togglePanel("felipeartur/ai-usagebar:panel")
end

report = noctalia.state.get("report")
failure = asFailure(noctalia.state.get("error"))
local published = noctalia.state.get("active_account")
activeLabel = type(published) == "string" and published or ""

-- The ticks move with the clock, so redraw without waking the CLI.
noctalia.setUpdateInterval(30000)
render()

function update()
    render()
end
