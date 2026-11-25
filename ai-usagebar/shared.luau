--!nonstrict
-- What the capsule and the panel both need, in one copy, so the parsing and the
-- severity tiers cannot drift between two entries that agree on screen.

local M = {}

-- Tabler has no Anthropic mark, so providers without a brand glyph use a
-- semantic one. The glyph is identity: it carries no colour of its own, so every
-- colour left in the panel means something.
local PROVIDER_GLYPHS = {
    anthropic = "asterisk-simple",
    anthropic_api = "asterisk-simple",
    openai = "brand-openai",
    zai = "bolt",
    openrouter = "route",
    deepseek = "fish",
    kimi = "moon",
    moonshot = "moon",
    kilo = "robot",
    novita = "cloud",
    grok = "brand-x",
    supergrok = "brand-x",
    antigravity = "sparkles",
    cursor = "cursor-text",
    minimax = "wave-square",
    kiro = "ghost",
    nous = "flask",
    ["opencode-go"] = "code",
    commandcode = "terminal-2",
    copilot = "brand-github-copilot",
    gemini = "brand-google",
    deepinfra = "cloud",
    grokbot = "brand-x",
    ollama = "cloud",
    orcarouter = "route",
    modelstudio = "cloud",
    lyceum = "book",
    devin = "terminal-2",
    cline = "terminal-2",
    ["muse-code"] = "code",
    synthetic = "flask",
    droid = "robot",
    deeprelay = "route",
    mistral = "wind",
}

local PROVIDER_DASHBOARDS = {
    droid = "https://app.factory.ai/",
    deeprelay = "https://deeprelay.ai/",
    mistral = "https://console.mistral.ai/",
    anthropic = "https://claude.ai/settings/usage",
    anthropic_api = "https://console.anthropic.com/",
    openai = "https://chatgpt.com/codex/settings/usage",
    openrouter = "https://openrouter.ai/activity",
    cursor = "https://www.cursor.com/settings",
    deepseek = "https://platform.deepseek.com/",
    zai = "https://z.ai",
    kimi = "https://platform.moonshot.cn/",
    moonshot = "https://platform.moonshot.cn/",
    grok = "https://console.x.ai/",
    supergrok = "https://grok.com/",
    gemini = "https://aistudio.google.com/",
    copilot = "https://github.com/settings/copilot",
    minimax = "https://platform.minimaxi.com/",
    antigravity = "https://antigravity.google/",
    kilo = "https://app.kilo.ai/usage",
    novita = "https://novita.ai/console",
    kiro = "https://app.kiro.dev/",
    nous = "https://portal.nousresearch.com/",
    ["opencode-go"] = "https://opencode.ai/console/",
    commandcode = "https://commandcode.ai/signin",
    deepinfra = "https://deepinfra.com/",
    grokbot = "https://x.ai/bot",
    ollama = "https://ollama.com/settings",
    orcarouter = "https://www.orcarouter.ai/",
    modelstudio = "https://modelstudio.console.alibabacloud.com/",
    lyceum = "https://dashboard.lyceum.technology/",
    devin = "https://app.devin.ai/",
    cline = "https://app.cline.bot/",
    ["muse-code"] = "https://dev.meta.ai/",
    synthetic = "https://synthetic.new/",
}

function M.baseProvider(id)
    return (tostring(id or ""):match("^[^@]+") or "")
end

function M.providerGlyph(id, brand)
    local mark = type(brand) == "string" and PROVIDER_GLYPHS[brand] or nil
    return mark or PROVIDER_GLYPHS[M.baseProvider(id)] or "brain"
end

function M.providerDashboard(id)
    return PROVIDER_DASHBOARDS[M.baseProvider(id)]
end

-- Ask the poller for a read. `at` is never read: it is there so two requests in
-- a row differ, and nowMs is the only sub-second clock the API has.
function M.requestRefresh()
    noctalia.state.set("command", { action = "refresh", at = noctalia.nowMs() })
end

-- Free text the CLI wrote to complain rather than to report; it marks those by
-- writing `error:` into the line. Asked here and nowhere else, so the panel and
-- the capsule cannot disagree about which lines are data.
function M.saysError(value)
    return tostring(value or ""):lower():find("error:") ~= nil
end

function M.transportError(value)
    return tostring(value or ""):lower():match("http%s*:?%s*%d%d%d") ~= nil
end

local function terminalAuthText(value)
    local text = tostring(value or ""):lower()
    local status = text:match("http%s*:?%s*401") ~= nil
        or text:match("http%s*:?%s*403") ~= nil
    local rejected = text:find("reject", 1, true) ~= nil
        or text:find("invalid", 1, true) ~= nil
        or text:find("expired", 1, true) ~= nil
        or text:find("forbidden", 1, true) ~= nil
        or text:find("unauthorized", 1, true) ~= nil
    return status and text:find("auth", 1, true) ~= nil and rejected
end

-- The CLI owns cache validity; a dated ready snapshot stays visible as stale.
local function cachedReading(entry)
    return type(entry) == "table" and entry.status == "ready" and entry.stale == true
        and M.parseIso(entry.fetched_at) ~= nil
        and ((type(entry.metrics) == "table" and #entry.metrics > 0) or M.balanceText(entry) ~= nil)
end

function M.terminalAuth(entry)
    if type(entry) ~= "table" then return false end
    if terminalAuthText(entry.error) then return true end
    local sections = type(entry.sections) == "table" and entry.sections or {}
    for _, section in ipairs(sections) do
        if type(section) == "table" and section.type == "text"
            and terminalAuthText(tostring(section.label or "") .. " "
                .. tostring(section.value or "")) then
            return true
        end
    end
    return false
end

-- A provider the CLI is no longer reading: the entry either fails outright, or
-- keeps serving cached numbers with a warning saying why they stopped moving.
-- Both mean the readings are a record, not a gauge.
function M.warning(entry)
    if type(entry) ~= "table" then return "" end
    local direct = noctalia.string.trim(tostring(entry.error or ""))
    if direct ~= "" then return direct end
    local sections = type(entry.sections) == "table" and entry.sections or {}
    for _, section in ipairs(sections) do
        if type(section) == "table" and section.type == "text" then
            local value = tostring(section.value or "")
            if M.saysError(value) then
                return noctalia.string.trim(value)
            end
        end
    end
    return ""
end

function M.unavailable(entry)
    if cachedReading(entry) then return false end
    if type(entry) ~= "table" then return true end
    if entry.status == "error" or M.warning(entry) ~= "" then return true end
    if entry.stale ~= true then return false end
    local sections = type(entry.sections) == "table" and entry.sections or {}
    for _, section in ipairs(sections) do
        if type(section) == "table" and section.type == "text"
            and (M.transportError(section.label) or M.transportError(section.value)) then
            return true
        end
    end
    return false
end

-- A parser failure says nothing about the account's availability.
function M.readFailure(entry)
    return type(entry) == "table" and entry.status == "error"
        and tostring(entry.error or ""):find("^schema mismatch:") ~= nil
end

-- Anything else in the `error` slot means no failure.
M.NO_FAILURE = { code = "", detail = "" }

function M.asFailure(value)
    if type(value) ~= "table" then return M.NO_FAILURE end
    return {
        code = type(value.code) == "string" and value.code or "",
        detail = type(value.detail) == "string" and value.detail or "",
    }
end

-- "2026-08-15T11:29:59.872624Z" -> unix seconds. The stamps are UTC and
-- os.time() reads its table as local, so the offset is measured and added back.
-- Force standard time on both conversions: DST must not normalize the UTC
-- fields through a nonexistent or ambiguous local wall time.
function M.parseIso(value)
    if type(value) ~= "string" or #value > 64 then return nil end
    local y, mo, d, h, mi, s, tail = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
    if y == nil then return nil end
    y, mo, d, h, mi, s = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
    if y < 1 or mo < 1 or mo > 12 or d < 1 or h > 23 or mi > 59 or s > 59 then return nil end
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if y % 400 == 0 or (y % 4 == 0 and y % 100 ~= 0) then days[2] = 29 end
    if d > days[mo] then return nil end
    local zone = tail:match("^%.%d+(.+)$") or tail
    local offset = 0
    if zone ~= "Z" then
        local sign, hours, minutes = zone:match("^([+-])(%d%d):(%d%d)$")
        if sign == nil or tonumber(hours) > 23 or tonumber(minutes) > 59 then return nil end
        offset = (tonumber(hours) * 3600 + tonumber(minutes) * 60) * (sign == "+" and 1 or -1)
    end
    local asLocal = os.time({
        year = y, month = mo, day = d,
        hour = h, min = mi, sec = s,
        isdst = false,
    })
    local utc = os.date("!*t", asLocal)
    utc.isdst = false
    local utcAsLocal = os.time(utc)
    return asLocal + (asLocal - utcAsLocal) - offset
end

local function formatDuration(seconds)
    if seconds <= 0 then return noctalia.tr("ui.now") end
    local minutes = math.floor(seconds / 60)
    local days = math.floor(minutes / 1440)
    local hours = math.floor((minutes % 1440) / 60)
    local rest = minutes % 60
    if days > 0 then return string.format("%dd %dh", days, hours) end
    if hours > 0 then return string.format("%dh %dm", hours, rest) end
    return string.format("%dm", rest)
end

local function formatFixedDuration(seconds)
    if seconds <= 0 then return noctalia.tr("ui.now") end
    local minutes = math.floor(seconds / 60)
    local days = math.floor(minutes / 1440)
    local hours = math.floor((minutes % 1440) / 60)
    local rest = minutes % 60
    if days > 0 then return string.format("%dd %dh", days, hours) end
    return string.format("%dh %02dm", hours, rest)
end

function M.countdown(section)
    local at = M.parseIso(section and section.reset_at)
    if at == nil then return "" end
    return formatDuration(at - os.time())
end

function M.fixedCountdown(section)
    local at = M.parseIso(section and section.reset_at)
    if at == nil then return "" end
    return formatFixedDuration(at - os.time())
end

function M.resetDescription(section, fixed)
    local left = fixed and M.fixedCountdown(section) or M.countdown(section)
    if left == "" then return "" end
    local regen = type(section) == "table" and section.regen or nil
    if type(regen) == "string" and noctalia.string.trim(regen) ~= "" then
        return noctalia.tr("ui.regenerates_in", { amount = regen, time = left })
    end
    return left
end

-- Where the countdown lands: "14:20" today, "Sat 14:20" past midnight, a date
-- once a weekday stops naming one day.
function M.resetClock(section)
    local at = M.parseIso(section and section.reset_at)
    if at == nil then return "" end
    local clock = noctalia.formatTime(noctalia.timeFormat(), at)
    if os.date("%Y-%m-%d", at) == os.date("%Y-%m-%d") then return clock end
    -- Prepended rather than folded into the pattern: the host's format grammar
    -- passes unknown text through verbatim, so "ddd" would render as the word.
    if at - os.time() > 6 * 86400 then return os.date("%d %b", at) .. " " .. clock end
    return os.date("%a", at) .. " " .. clock
end

-- How much of the window is gone, out of "Resets in 1h 58m · 60% elapsed".
function M.elapsedPercent(detail)
    local value = tostring(detail or ""):match("([%+%-]?[%d%.]+)%%%s*elapsed")
    return value ~= nil and tonumber(value) or nil
end

-- The pace is the trailing segment of "Resets in 1h 58m · 60% elapsed · 30pts
-- ahead". `elapsed` sitting there means the reading carries no pace at all.
-- Returns that segment's text, then the points and the direction inside it.
function M.pace(detail)
    local text = tostring(detail or "")
    local points, word = text:match("(%d+)pts%s+(%a+)")
    points = tonumber(points)
    if not text:find("·") then return "", points, word end
    local last = ""
    for part in text:gmatch("[^·]+") do last = part end
    last = noctalia.string.trim(last)
    if last:find("elapsed") then return "", points, word end
    return last, points, word
end

-- Kept next to the role both entries colour with, so the tiers cannot be edited
-- in one file and forgotten in the other. `low` falls through to 0, like
-- anything the CLI adds later.
M.SEVERITY_RANK = { critical = 3, high = 2, mid = 1 }

local function isCritical(metric)
    if type(metric) ~= "table" then return false end
    local sev = tostring(metric.severity or "")
    local pct = tonumber(metric.percent) or 0
    return sev == "critical" or pct >= 100
end
M.isCritical = isCritical

-- Severity is a warning, not proof of exhaustion. Only a full quota blocks use.
function M.blockingMetric(metrics)
    local blocking = nil
    for _, metric in ipairs(metrics or {}) do
        if type(metric) == "table" and (tonumber(metric.percent) or 0) >= 100 then
            local reset = M.parseIso(metric.reset_at) or -1
            local previous = M.parseIso(blocking and blocking.reset_at) or -1
            if blocking == nil or reset > previous then blocking = metric end
        end
    end
    return blocking
end

-- A model pool limits that model alone. Provider summaries use shared windows
-- when present; a pool-only report still has useful quota to display.
local function sharedMetrics(metrics)
    local shared, pools = {}, {}
    for _, metric in ipairs(metrics or {}) do
        if type(metric) == "table" then
            local target = metric.model_pool == true and pools or shared
            target[#target + 1] = metric
        end
    end
    return #shared > 0 and shared or pools
end

function M.headline(entry)
    if type(entry) ~= "table" or type(entry.metrics) ~= "table" then return nil end
    local metrics = sharedMetrics(entry.metrics)
    if #metrics == 0 then return nil end

    local blocking = M.blockingMetric(metrics)
    if blocking ~= nil then return blocking end

    -- 1. For Antigravity: always follow active session usage across models
    if M.baseProvider(entry.id) == "antigravity" then
        local seen = {}
        local best = nil
        local bestPct = -1
        for _, metric in ipairs(metrics) do
            if type(metric) == "table" and metric.label ~= nil and metric.label ~= "" then
                local model = tostring(metric.label)
                if not seen[model] then
                    seen[model] = true
                    local pct = tonumber(metric.percent) or 0
                    if pct > bestPct then
                        best = metric
                        bestPct = pct
                    end
                end
            end
        end
        if best ~= nil then return best end
    end

    -- Otherwise keep the primary window selected by the CLI.
    for _, metric in ipairs(metrics) do
        if type(metric) == "table" then return metric end
    end
    return nil
end

-- A provider can report a balance instead of a quota. The CLI then sends no
-- percentage metrics and puts the figure in a `text` section (DeepSeek
-- `Balance: $2.90`, Nous `Total usable credits: 8.19`). Pick the one a reader
-- would want on the bar: a total or balance first, then a credit/remaining
-- line, and never a reset countdown. Returns nil for providers that already
-- carry a headline metric, so the percentage path is untouched.
function M.balanceText(entry)
    if type(entry) ~= "table" or M.headline(entry) ~= nil then return nil end
    local sections = type(entry.sections) == "table" and entry.sections or nil
    if sections == nil then return nil end

    local credit = nil
    for _, section in ipairs(sections) do
        if type(section) == "table" and section.type == "text" then
            local value = noctalia.string.trim(tostring(section.value or ""))
            if value ~= "" and not M.saysError(value) then
                local label = tostring(section.label or ""):lower()
                if label:find("total", 1, true) or label:find("balance", 1, true) then
                    return value
                end
                if credit == nil
                    and (label:find("credit", 1, true) or label:find("remaining", 1, true)) then
                    credit = value
                end
            end
        end
    end
    return credit
end

-- Explicit pins require a real matching window; positional fallback would turn
-- a missing monthly quota into a plausible but unrelated weekly reading.
function M.metricWindow(metric)
    if type(metric) ~= "table" then return nil end
    local seconds = tonumber(metric.window_secs)
    if seconds ~= nil then
        if seconds > 0 and seconds <= 86400 then return "session" end
        if seconds == 604800 then return "weekly" end
        if seconds >= 2419200 and seconds <= 2678400 then return "monthly" end
        return nil
    end
    local label = tostring(metric.label or ""):lower()
    if label:find("month", 1, true) or label:find("30d", 1, true) then return "monthly" end
    if label:find("week", 1, true) or label:find("7d", 1, true) then return "weekly" end
    if label:find("session", 1, true) or label:find("hour", 1, true)
        or label:match("%d+h") then return "session" end
    return nil
end

function M.isRemaining(metric, display)
    return (type(metric) == "table" and metric.reading == "left") or display == "remaining"
end

local function finiteNumber(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

function M.displayPercent(metric, display)
    if type(metric) ~= "table" then return nil end
    local percent = finiteNumber(metric.percent)
    if percent == nil then return nil end
    if M.isRemaining(metric, display) then return math.max(0, 100 - percent) end
    return percent
end

-- Keep precise figures in text; meters and severity still use the CLI's integer.
function M.percentText(metric, display)
    local percent = M.displayPercent(metric, display)
    if percent == nil then return "—" end
    local precise = finiteNumber(metric.percent_precise)
    if precise ~= nil then
        percent = M.isRemaining(metric, display) and math.max(0, 100 - precise) or precise
        return string.format("%.2f", percent):gsub("0+$", ""):gsub("%.$", "") .. "%"
    end
    return string.format("%.0f%%", percent)
end

-- The report names the headline field: balances are already formatted and
-- must not be inverted when the user chooses remaining percentages.
function M.metricText(metric, display)
    if type(metric) ~= "table" then return "—" end
    if metric.headline == "value" then
        local value = type(metric.value) == "string" and noctalia.string.trim(metric.value) or ""
        return value ~= "" and value or "—"
    end
    return M.percentText(metric, display)
end

function M.modelGlyph(label)
    local lower = tostring(label or ""):lower()
    if lower:find("oss", 1, true) or lower:find("claude", 1, true) then return "robot" end
    if lower:find("gemini", 1, true) then return "brand-google" end
    if lower:find("gpt", 1, true) or lower:find("openai", 1, true) then return "brand-openai" end
    return "sparkles"
end

function M.modelDisplayName(label)
    local lower = tostring(label or ""):lower()
    if lower:find("oss", 1, true) or lower:find("claude", 1, true) then return tostring(label or "") end
    if lower:find("gpt", 1, true) or lower:find("openai", 1, true) then return "GPT" end
    return tostring(label or "")
end

function M.modelHeadlines(entry)
    if type(entry) ~= "table" or type(entry.metrics) ~= "table" then return {} end
    if M.baseProvider(entry.id) ~= "antigravity" then return {} end

    local order = {}
    local byModel = {}
    for _, metric in ipairs(entry.metrics) do
        if type(metric) == "table" and metric.label ~= nil and metric.label ~= "" then
            local model = tostring(metric.label)
            if byModel[model] == nil then
                byModel[model] = {}
                order[#order + 1] = model
            end
            byModel[model][#byModel[model] + 1] = metric
        end
    end

    local result = {}
    for _, model in ipairs(order) do
        local modelMetrics = byModel[model]
        local sessionMetric, weeklyMetric = M.dualMetrics(modelMetrics)
        sessionMetric = sessionMetric or weeklyMetric
        local blockingMetric = M.blockingMetric(modelMetrics)
        if sessionMetric ~= nil then
            result[#result + 1] = {
                model = model,
                displayName = M.modelDisplayName(model),
                glyph = M.modelGlyph(model),
                metric = sessionMetric,
                metrics = modelMetrics,
                blockingMetric = blockingMetric,
            }
        end
    end
    return result
end

-- Extracts (shortMetric, weeklyMetric) where shortMetric represents the 5-hour
-- session limit and weeklyMetric represents the 7-day rate limit.
function M.dualMetrics(metrics)
    if type(metrics) ~= "table" then return nil, nil end
    metrics = sharedMetrics(metrics)
    if #metrics == 0 then return nil, nil end
    if #metrics == 1 then
        local m = metrics[1]
        local w = tonumber(m.window_secs)
        local lbl = tostring(m.label or ""):lower()
        if (w ~= nil and w > 86400) or lbl:find("week", 1, true) or lbl:find("7d", 1, true) then
            return nil, m
        end
        return m, nil
    end

    local shortMetric = nil
    local weeklyMetric = nil

    for _, m in ipairs(metrics) do
        local w = tonumber(m.window_secs)
        local lbl = tostring(m.label or ""):lower()
        if w ~= nil then
            if w <= 86400 and shortMetric == nil then
                shortMetric = m
            elseif w > 86400 and weeklyMetric == nil then
                weeklyMetric = m
            end
        elseif lbl:find("5h", 1, true) or lbl:find("session", 1, true) or lbl:find("hour", 1, true) then
            if shortMetric == nil then shortMetric = m end
        elseif lbl:find("week", 1, true) or lbl:find("7d", 1, true) then
            if weeklyMetric == nil then weeklyMetric = m end
        end
    end

    if shortMetric ~= nil and weeklyMetric ~= nil then
        return shortMetric, weeklyMetric
    end

    if shortMetric ~= nil and weeklyMetric == nil and #metrics >= 2 then
        for _, m in ipairs(metrics) do
            if m ~= shortMetric then return shortMetric, m end
        end
    end

    if weeklyMetric ~= nil and shortMetric == nil and #metrics >= 2 then
        for _, m in ipairs(metrics) do
            if m ~= weeklyMetric then return m, weeklyMetric end
        end
    end

    return metrics[1], metrics[2]
end

function M.entries(report)
    if type(report) ~= "table" or type(report.entries) ~= "table" then return {} end
    local visible, positions = {}, {}
    for _, entry in ipairs(report.entries) do
        if type(entry) == "table" and (cachedReading(entry) or not M.terminalAuth(entry))
            and (not M.unavailable(entry) or M.readFailure(entry)) then
            visible[#visible + 1] = entry
            positions[entry] = #visible
        end
    end
    table.sort(visible, function(a, b)
        local aMetric = M.headline(a)
        local bMetric = M.headline(b)
        local aRank = M.SEVERITY_RANK[tostring(aMetric and aMetric.severity or "")] or 0
        local bRank = M.SEVERITY_RANK[tostring(bMetric and bMetric.severity or "")] or 0
        if aRank ~= bRank then return aRank > bRank end
        local aPercent = type(aMetric) == "table" and tonumber(aMetric.percent) or -1
        local bPercent = type(bMetric) == "table" and tonumber(bMetric.percent) or -1
        if aPercent ~= bPercent then return aPercent > bPercent end
        return positions[a] < positions[b]
    end)
    return visible
end

-- A provider can report more than it was given, so clamp before this becomes a
-- bar width.
function M.ratio(percent)
    local value = (tonumber(percent) or 0) / 100
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

-- The CLI tiers every percentage; copying its thresholds here would be a second
-- source of truth. `calm` is for when it raised nothing.
--
-- `high` is deliberately not `tertiary`: themes may make that role dark, and in
-- the stock dark theme it lands at 2.8:1 on a card, below the 3.9:1 of the muted
-- text it is supposed to outrank.
function M.severityRole(section, calm)
    local severity = tostring(section and section.severity or "")
    if severity == "critical" then return "error" end
    if severity == "high" then return "secondary" end
    return calm
end

-- Project the CLI ranking without recomputing its order, score or recommendation.
function M.priorities(report)
    if type(report) ~= "table" or type(report.entries) ~= "table"
        or type(report.ranking) ~= "table" then return nil end
    local accounts, seen, rows = {}, {}, {}
    for _, entry in ipairs(report.entries) do
        if type(entry) == "table" and type(entry.id) == "string" then accounts[entry.id] = entry end
    end
    local statuses = { priority=true, on_track=true, blocked=true, unavailable=true, unknown=true }
    local recommended = type(report.recommendation) == "table" and report.recommendation.entry_id or nil
    local function percent(value)
        local n = finiteNumber(value)
        return n ~= nil and n >= 0 and n <= 100 and n or nil
    end
    for index, row in ipairs(report.ranking) do
        if index > 128 or #rows >= 64 then break end
        local id = type(row) == "table" and row.entry_id or nil
        local entry = type(id) == "string" and accounts[id] or nil
        if entry ~= nil and not seen[id] then
            seen[id] = true
            local status = type(row.status) == "string" and statuses[row.status] and row.status or "unknown"
            local reset = type(row.reset_at) == "string" and #row.reset_at <= 64 and row.reset_at or nil
            local parsedReset = nil
            if reset ~= nil then
                local ok, parsed = pcall(M.parseIso, reset)
                if ok and parsed ~= nil then
                    parsedReset = parsed
                else
                    reset = nil
                end
            end
            local expired = parsedReset ~= nil and parsedReset <= os.time()
            local stale = entry.stale == true or row.stale == true or report.stale == true or expired
            rows[#rows + 1] = {
                entry = entry, status = status, stale = stale, expired = expired,
                urgent = row.urgent == true and status == "priority",
                session_exhausted = row.session_exhausted == true,
                unused_percent = percent(row.unused_percent),
                remaining_percent = percent(row.remaining_percent),
                reset_at = reset,
                recommended = id == recommended and status == "priority"
                    and entry.status == "ready" and not stale,
            }
        end
    end
    return rows
end

-- ── Claude profiles ───────────────────────────────────────────────────────────
-- A profile is one CLI account: `anthropic@<label>` in the report and `<label>`
-- in `ai-usagebar account status --json`. The bar draws the active one and the
-- panel lists them all in `profiles` order.

local CLAUDE = "anthropic"

-- Labels the panel may hand to `ai-usagebar account switch`. The poller checks
-- again before it runs anything.
function M.isProfileLabel(label)
    return type(label) == "string" and #label <= 64 and label:match("^[%w][%w._%-]*$") ~= nil
end

-- The account label of a Claude entry, or nil for the bare default entry and for
-- every other provider.
function M.profileLabel(entry)
    if type(entry) ~= "table" then return nil end
    local base, label = tostring(entry.id or ""):match("^([^@]+)@(.+)$")
    if base ~= CLAUDE or not M.isProfileLabel(label) then return nil end
    return label
end

-- How far through its window a reading is, 0..100. Worked out from `reset_at`
-- so the figure moves between polls; the CLI's "60% elapsed" is the fallback.
-- nil once the window has rolled over, because the next one has not been read.
function M.windowElapsed(metric)
    if type(metric) ~= "table" then return nil end
    local reset = M.parseIso(metric.reset_at)
    local window = finiteNumber(metric.window_secs)
    if reset ~= nil and window ~= nil and window > 0 then
        local left = reset - os.time()
        if left < 0 then return nil end
        if left <= window then return (window - left) / window * 100 end
    end
    local elapsed = M.elapsedPercent(metric.detail)
    if elapsed ~= nil and elapsed >= 0 and elapsed <= 100 then return elapsed end
    return nil
end

local function quotaMetric(metrics, window)
    local fallback = nil
    for _, metric in ipairs(metrics) do
        if type(metric) == "table" and metric.model_pool ~= true and M.metricWindow(metric) == window then
            -- A model pool such as "Fable (7d)" shares the 7-day window with the
            -- overall quota, so the label picks the overall one.
            if window ~= "weekly" or tostring(metric.label or ""):lower():find("^weekly") then return metric end
            fallback = fallback or metric
        end
    end
    return fallback
end

-- One quota window of an entry, ready to draw. `window` is "session" or
-- "weekly". `percent` is the used share (0 when the window is absent),
-- `elapsed` is how far through the window we are (nil when unknown or absent),
-- and `ahead` says usage is running ahead of time.
function M.windowGauge(entry, window)
    local metrics = type(entry) == "table" and type(entry.metrics) == "table" and entry.metrics or {}
    local metric = quotaMetric(metrics, window)
    if metric == nil then return { metric = nil, percent = 0, elapsed = nil, ahead = false } end
    local percent = finiteNumber(metric.percent) or 0
    local elapsed = M.windowElapsed(metric)
    return {
        metric = metric,
        percent = percent,
        elapsed = elapsed,
        ahead = elapsed ~= nil and percent > elapsed,
    }
end

local PILL_HEIGHT = 8
local TICK_WIDTH = 2
local PILL_TRACK = "on_surface/0.14"
local PILL_TICK = "on_surface"
local NO_LIMIT_OUTLINE = "on_surface/0.35"

-- A window the CLI does not report is a limit the account does not have.
M.NO_LIMIT_TEXT = "∞"

-- The percentage beside a pill.
function M.gaugeText(gauge, display)
    if type(gauge) ~= "table" or gauge.metric == nil then return M.NO_LIMIT_TEXT end
    return M.percentText(gauge.metric, display)
end

-- One `windowGauge` drawn `width` px wide, for the bar and the panel cards.
-- `ui` is passed in because this module is loaded outside the UI hosts too.
--
-- The host has no overlay, so the pill is a row of boxes laid end to end: fill
-- up to the used share, track after it, and a tick box at the elapsed share
-- that splits whichever of the two it falls in. The fill takes the warning
-- colour when usage is ahead of the tick. A window the account has no limit
-- for draws hollow: an outline with no track and no tick, which is not 0% of
-- a limit.
function M.quotaPill(ui, gauge, width)
    if type(gauge) ~= "table" or gauge.metric == nil then
        return ui.row({ width = width, height = PILL_HEIGHT, minWidth = width, radius = 2,
            border = NO_LIMIT_OUTLINE, borderWidth = 1 }, { ui.spacer({ key = "rest", flexGrow = 1 }) })
    end
    local used = math.floor(width * M.ratio(gauge.percent) + 0.5)
    local fill = gauge.ahead and "secondary" or "primary"
    local segments = {}
    local function add(kind, size)
        if size <= 0 then return end
        segments[#segments + 1] = ui.box({
            key = kind .. "-" .. tostring(#segments),
            width = size,
            height = PILL_HEIGHT,
            radius = kind == "tick" and 1 or 2,
            fill = kind == "fill" and fill or kind == "tick" and PILL_TICK or nil,
        })
    end

    if gauge.elapsed == nil then
        add("fill", used)
    else
        local tick = math.floor(width * M.ratio(gauge.elapsed) + 0.5) - math.floor(TICK_WIDTH / 2)
        tick = math.max(0, math.min(width - TICK_WIDTH, tick))
        if used <= tick then
            add("fill", used)
            add("track", tick - used)
            add("tick", TICK_WIDTH)
        else
            add("fill", tick)
            add("tick", TICK_WIDTH)
            add("fill", used - tick - TICK_WIDTH)
        end
    end
    segments[#segments + 1] = ui.spacer({ key = "rest", flexGrow = 1 })

    return ui.row({ width = width, height = PILL_HEIGHT, minWidth = width, radius = 2,
        fill = PILL_TRACK, gap = 0, align = "center" }, segments)
end

-- Whether the session or the overall weekly window is used up. Model pools
-- do not count: a full Fable window leaves the account usable.
function M.atLimit(entry)
    if type(entry) ~= "table" then return false end
    for _, window in ipairs({ "session", "weekly" }) do
        local gauge = M.windowGauge(entry, window)
        if gauge.metric ~= nil and gauge.percent >= 100 then return true end
    end
    return false
end

-- Whether the account's monthly extra usage (pay-as-you-go spending past the
-- plan limits) still has room. The CLI reports it as an "Extra usage" metric
-- whose percent is the share of the monthly cap spent; an account without
-- extra usage has no such metric.
function M.extraUsageLeft(entry)
    if type(entry) ~= "table" or type(entry.metrics) ~= "table" then return false end
    for _, metric in ipairs(entry.metrics) do
        if type(metric) == "table" and tostring(metric.label or ""):lower():find("^extra usage") then
            local percent = finiteNumber(metric.percent)
            return percent ~= nil and percent < 100
        end
    end
    return false
end

-- Quota left in both the session and the overall weekly window.
function M.hasUsageLeft(entry)
    if type(entry) ~= "table" or entry.status == "error" or M.unavailable(entry) then return false end
    return not M.atLimit(entry)
end

-- The reset credits an entry holds, from the CLI's "Reset credits" block:
-- { title, expires } per credit, in the CLI's order. A line reads
-- "<title> · expires <date> (<time left>)"; `expires` is the time left, or the
-- whole expiry when the line has no countdown, or "" when it has no expiry.
function M.resetCredits(entry)
    local credits = {}
    local sections = type(entry) == "table" and type(entry.sections) == "table" and entry.sections or {}
    for _, section in ipairs(sections) do
        if type(section) == "table" and section.type == "block" and section.label == "Reset credits"
            and type(section.body) == "table" then
            for _, line in ipairs(section.body) do
                local text = noctalia.string.trim(tostring(line))
                local title, expiry = text:match("^(.-)%s+·%s+(.+)$")
                if title == nil then title, expiry = text, "" end
                local left = expiry:match("%(([^()]+)%)%s*$")
                if title ~= "" then
                    credits[#credits + 1] = { title = title, expires = left or expiry }
                end
            end
        end
    end
    return credits
end

-- The entry the bar draws: the active account, or the bare default entry when
-- no account is active or the report does not carry it.
function M.activeProfile(report, activeLabel)
    local fallback = nil
    for _, entry in ipairs(M.entries(report)) do
        local label = M.profileLabel(entry)
        if label ~= nil and label == activeLabel then return entry end
        if tostring(entry.id) == CLAUDE then fallback = entry end
    end
    return fallback
end

-- Every entry the panel lists, in display order: the active account, then
-- entries with quota left, then the rest. Each group runs from the soonest
-- weekly reset; an entry without one goes last in its group. The bare default
-- entry is left out when named accounts exist, because it is the active
-- account read a second time.
--
-- Returns { entry, label, active, usable, limited, extraUsage } rows, where
-- `extraUsage` says a limited account can still run on extra usage.
function M.profiles(report, activeLabel)
    local all = M.entries(report)
    local named = false
    for _, entry in ipairs(all) do
        if M.profileLabel(entry) ~= nil then named = true; break end
    end
    local rows = {}
    for _, entry in ipairs(all) do
        if not (named and tostring(entry.id) == CLAUDE) then
            local label = M.profileLabel(entry)
            local weekly = M.windowGauge(entry, "weekly").metric
            rows[#rows + 1] = {
                entry = entry,
                label = label,
                active = label ~= nil and label == activeLabel,
                usable = M.hasUsageLeft(entry),
                limited = M.atLimit(entry),
                extraUsage = M.extraUsageLeft(entry),
                reset = M.parseIso(weekly and weekly.reset_at),
            }
        end
    end
    local function group(row) return row.active and 0 or row.usable and 1 or 2 end
    table.sort(rows, function(a, b)
        if group(a) ~= group(b) then return group(a) < group(b) end
        if a.reset ~= b.reset then
            if a.reset == nil then return false end
            if b.reset == nil then return true end
            return a.reset < b.reset
        end
        return tostring(a.entry.id) < tostring(b.entry.id)
    end)
    for _, row in ipairs(rows) do row.reset = nil end
    return rows
end

return M
