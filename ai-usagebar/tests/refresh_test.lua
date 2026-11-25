-- Small host harness for the poller state machine and provider visual metadata.

local function read(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local values, watchers = {}, {}
local commands, callbacks, timeouts = {}, {}, {}
-- `account status` and `account switch` run as argv tables; they are kept apart
-- so the usage reads above keep their indexes.
local accountRuns = {}
local notifications = {}
local decodedReport = { entries = {} }
local now = 5000
local intervals = {}

local state = {
    get = function(key) return values[key] end,
    set = function(key, value)
        values[key] = value
        if watchers[key] then watchers[key](value) end
    end,
    watch = function(key, callback) watchers[key] = callback end,
}

local noctalia = {
    state = state,
    nowMs = function() return now end,
    getConfig = function(key) return key == "refresh_minutes" and 5 or nil end,
    setUpdateInterval = function(ms) intervals[#intervals + 1] = ms end,
    runAsync = function(command, callback, timeout)
        if type(command) == "table" then
            accountRuns[#accountRuns + 1] = { argv = command, callback = callback, timeout = timeout }
            return true
        end
        commands[#commands + 1] = command
        callbacks[#callbacks + 1] = callback
        timeouts[#timeouts + 1] = timeout
        return true
    end,
    json = { decode = function() return decodedReport end },
    notify = function(title, message)
        notifications[#notifications + 1] = { title = title, message = message }
    end,
    tr = function(key) return key end,
    string = { trim = function(value) return value end },
}

local env = setmetatable({ noctalia = noctalia }, { __index = _G })
env.require = function(path)
    assert(path == "./shared.luau")
    return assert(load(read("shared.luau"), "shared", "t", env))()
end
local service = assert(load(read("service.luau"), "service", "t", env))
service()

assert(#callbacks == 1, "service should start one initial refresh")
assert(timeouts[1] == 60000, "usage polling should allow 60s for slower provider and agy reads")
env.onIpc("refresh")
assert(#callbacks == 1, "refresh while busy should be coalesced")
assert(values.refresh_queued == true, "coalesced refresh should be visible as queued")

now = 7000
callbacks[1]({ exitCode = 0, stdout = "{}", stderr = "" })
assert(#callbacks == 2, "queued refresh should start after the first callback")
assert(values.refresh_queued == false, "queued state should clear when refresh starts")
assert(values.polling == true, "queued refresh should become the active poll")
assert(intervals[#intervals] == 5 * 60 * 1000, "active refresh should restore the configured interval")

callbacks[2]({ timedOut = true, exitCode = 0, stdout = '{"entries":[]}', stderr = "" })
assert(values.error.code == "timed_out", "a timed-out command must not publish valid-looking stdout")

decodedReport = { entries = { { id = "antigravity", status = "error",
    error = "credentials error: Antigravity: no local server found.", metrics = {} } } }
now = 9000
env.onIpc("refresh")
callbacks[3]({ exitCode = 0, stdout = "{}", stderr = "" })
assert(values.report.entries[1].status == "error"
    and values.report.entries[1].stale ~= true,
    "Antigravity without an earlier reading must stay unavailable")

decodedReport = { entries = { { id = "openai", display_name = "Codex api_key=topsecret123", status = "ready",
    metrics = { { label = "Session", percent = 10 },
        { label = "Weekly", percent = 100 } } } } }
now = 11000
env.onIpc("refresh")
callbacks[4]({ exitCode = 0, stdout = "{}", stderr = "" })
assert(#notifications == 0, "quota changes must not send notifications")

decodedReport = { entries = {
    { id = "antigravity", display_name = "Antigravity", status = "ready",
      fetched_at = "2026-09-24T12:00:00Z", metrics = { { label = "Gemini", percent = 42 } } },
    { id = "openai", display_name = "Codex", status = "ready", metrics = {} },
} }
now = 13000
env.onIpc("refresh")
callbacks[5]({ exitCode = 0, stdout = "{}", stderr = "" })

decodedReport = { entries = {
    { id = "antigravity", display_name = "Antigravity", status = "error",
      error = "credentials error: Antigravity: no local server found.", metrics = {} },
    { id = "openai", display_name = "Codex", status = "ready", metrics = {} },
} }
now = 15000
env.onIpc("refresh")
callbacks[6]({ exitCode = 0, stdout = "{}", stderr = "" })
local cached = values.report.entries[1]
assert(cached.id == "antigravity" and cached.metrics[1].percent == 42
    and cached.fetched_at == "2026-09-24T12:00:00Z" and cached.stale == true,
    "a transient Antigravity failure should retain the dated last reading")
assert(values.report.entries[2].id == "openai", "other providers should keep fresh readings")

decodedReport = { entries = { { id = "antigravity", status = "error",
    error = "credentials error: Antigravity: no local server found.", metrics = {} } } }
now = 17000
env.onIpc("refresh")
callbacks[7]({ exitCode = 0, stdout = "{}", stderr = "" })
assert(values.report.entries[1].metrics[1].percent == 42
    and values.report.entries[1].stale == true,
    "consecutive local-server failures should not make Antigravity disappear")

decodedReport = { entries = {
    { id = "antigravity", display_name = "Antigravity", status = "ready",
      fetched_at = "2026-09-24T12:05:00Z", metrics = { { label = "Gemini", percent = 35 } } },
} }
now = 19000
env.onIpc("refresh")
callbacks[8]({ exitCode = 0, stdout = "{}", stderr = "" })
assert(values.report.entries[1].metrics[1].percent == 35
    and values.report.entries[1].stale ~= true,
    "the next healthy Antigravity reading should replace the cached one")

-- Multi-account Antigravity: transient local-server fallback stays isolated per entry.id.
decodedReport = { entries = {
    { id = "antigravity", display_name = "Antigravity", status = "ready",
      fetched_at = "2026-09-24T12:10:00Z", metrics = { { label = "Gemini", percent = 18 } } },
    { id = "antigravity@t3-1", display_name = "Antigravity · t3-1", status = "ready",
      fetched_at = "2026-09-24T12:10:00Z", metrics = { { label = "Claude & GPT OSS", percent = 7 } } },
} }
now = 21000
env.onIpc("refresh")
callbacks[9]({ exitCode = 0, stdout = "{}", stderr = "" })

decodedReport = { entries = {
    { id = "antigravity", display_name = "Antigravity", status = "error",
      error = "credentials error: Antigravity: no local server found.", metrics = {} },
    { id = "antigravity@t3-1", display_name = "Antigravity · t3-1", status = "ready",
      fetched_at = "2026-09-24T12:15:00Z", metrics = { { label = "Claude & GPT OSS", percent = 12 } } },
} }
now = 23000
env.onIpc("refresh")
callbacks[10]({ exitCode = 0, stdout = "{}", stderr = "" })
assert(values.report.entries[1].id == "antigravity"
    and values.report.entries[1].stale == true
    and values.report.entries[1].metrics[1].percent == 18,
    "default Antigravity account should keep its own stale reading")
assert(values.report.entries[2].id == "antigravity@t3-1"
    and values.report.entries[2].stale ~= true
    and values.report.entries[2].metrics[1].percent == 12,
    "named Antigravity account should keep its fresh reading when default falls back")

local sharedEnv = setmetatable({ noctalia = noctalia }, { __index = _G })
local shared = assert(load(read("shared.luau"), "shared", "t", sharedEnv))()
local incompleteFailure = shared.asFailure({})
assert(incompleteFailure.code == "" and incompleteFailure.detail == "",
    "an incomplete failure table should behave as no failure")
-- A named account is drawn with its provider's glyph, not the fallback.
assert(shared.providerGlyph("anthropic@gmail") == shared.providerGlyph("anthropic"),
    "an account should inherit the provider's glyph")
assert(shared.providerGlyph("unknown") == "brain", "an unknown provider falls back")


local intervalBody = assert(read("service.luau"):match("local function intervalMs%(%)\n(.-)\nend"))
for _, case in ipairs({
    { 0, 60000 }, { 121, 7200000 }, { 1.5, 90000 },
    { 0/0, 300000 }, { math.huge, 300000 }, { -math.huge, 300000 },
}) do
    local host = { getConfig = function() return case[1] end }
    local interval = assert(load("return function()\n" .. intervalBody .. "\nend", "interval", "t",
        setmetatable({ noctalia = host }, { __index = _G })))()
    assert(interval() == case[2], "manual refresh settings must respect declared finite bounds")
end

-- Optional priorities use a fixed flag, never a command from report text.
do
    local clock, configured, decoded = 5000, true, nil
    local state, reads = {}, {}
    local host = {
        nowMs = function() return clock end,
        getConfig = function(key) if key == "show_priorities" then return configured end; return 5 end,
        setUpdateInterval = function() end,
        state = { get = function(k) return state[k] end, set = function(k,v) state[k]=v end, watch = function() end },
        string = { trim = function(v) return tostring(v):match("^%s*(.-)%s*$") end },
        json = { decode = function() return decoded end },
        runAsync = function(command, callback)
            if type(command) == "string" then reads[#reads+1]={command=command, callback=callback} end
            return true
        end,
    }
    local runtime = setmetatable({ noctalia=host }, { __index=_G })
    runtime.require = function() return assert(load(read("shared.luau"),"shared","t",runtime))() end
    assert(load(read("service.luau"),"service","t",runtime))()
    assert(reads[1].command == "ai-usagebar usage --json --priorities", "enabled priorities extend the single poll")
    reads[1].callback({exitCode=2, stderr="error: unexpected argument '--priorities' found", stdout=""})
    clock=7000; runtime.update()
    assert(#reads==2 and reads[2].command=="ai-usagebar usage --json", "an older CLI retries plain usage once")
    assert(state.priorities_supported==false, "unsupported priorities are explicit")
    decoded={entries={}}; reads[2].callback({exitCode=0,stdout="{}"})
    configured=false; clock=9000; runtime.onConfigChanged()
    assert(reads[3].command=="ai-usagebar usage --json", "disabling removes the flag")
    reads[3].callback({exitCode=0,stdout="{}"})
    configured=true; clock=11000; runtime.onConfigChanged()
    assert(reads[4].command=="ai-usagebar usage --json --priorities", "config changes allow a CLI upgrade to be retried")
end

-- Excessive CLI documents must leave the last reading intact and allow retries.
do
    local deep = {}
    local leaf = deep
    for _ = 1, 40 do leaf.child = {}; leaf = leaf.child end
    local wide = {}
    for i = 1, 20001 do wide[i] = i end
    local accounts = {}
    for index = 1, 129 do accounts[index] = { id = "openai@" .. index } end
    for _, case in ipairs({
        { stdout = "{}", document = { entries = accounts } },
        { stdout = string.rep(" ", 1024 * 1024 + 1), document = { entries = {} }, noDecode = true },
        { stdout = "{}", document = { entries = {}, metadata = deep } },
        { stdout = "{}", document = { entries = {}, metadata = wide } },
    }) do
        local previous = values.report
        decodedReport = case.document
        noctalia.json.decode = function()
            assert(not case.noDecode, "oversized stdout must not reach json.decode")
            return decodedReport
        end
        now = now + 3000
        env.onIpc("refresh")
        callbacks[#callbacks]({ exitCode = 0, stdout = case.stdout })
        assert(values.report == previous, "excessive documents must preserve cached report")
        assert(values.error.code == "too_large" and values.polling == false,
            "excessive documents must report too_large and release the poller")
        decodedReport = { entries = {}, optional = { old_cli = true } }
        noctalia.json.decode = function() return decodedReport end
        now = now + 3000
        local before = #callbacks
        env.onIpc("refresh")
        assert(#callbacks == before + 1, "rejected report must not leave refresh in flight")
        callbacks[#callbacks]({ exitCode = 0, stdout = "{}" })
        assert(values.report == decodedReport and values.error.code == "",
            "a small legacy report must recover after rejection")
    end
end

-- Every poll re-reads the active account and publishes its label alone.
do
    local function lastRun() return accountRuns[#accountRuns] end
    lastRun().callback({ exitCode = 2, stdout = "" })
    local before = #accountRuns
    now = now + 3000
    env.onIpc("refresh")
    assert(#accountRuns == before + 1, "every poll should read the active account")
    assert(table.concat(lastRun().argv, " ") == "ai-usagebar account status --json",
        "the status read should be the fixed argv")
    noctalia.json.decode = function()
        return { cli = { active_label = "work", active_account_uuid = "uuid",
            accounts = { { label = "work", email = "person@example.com", active = true } } } }
    end
    lastRun().callback({ exitCode = 0, stdout = "{}" })
    assert(values.active_account == "work", "the active label should be published")
    for key, value in pairs(values) do
        assert(not tostring(value):find("example.com", 1, true), "no e-mail may reach state: " .. key)
    end

    now = now + 3000
    env.onIpc("refresh")
    noctalia.json.decode = function() return { cli = { active_label = "bad label; rm" } } end
    lastRun().callback({ exitCode = 0, stdout = "{}" })
    assert(values.active_account == "", "a label that could not be switched to is dropped")

    now = now + 3000
    env.onIpc("refresh")
    lastRun().callback({ exitCode = 2, stdout = "", stderr = "unknown subcommand" })
    assert(values.active_account == "", "an older CLI without account status leaves no active account")
    noctalia.json.decode = function() return decodedReport end
    callbacks[#callbacks]({ exitCode = 0, stdout = "{}" })

    -- A queued usage read started another status read; answer it.
    if lastRun().argv[2] == "account" and lastRun().argv[3] == "status" then
        lastRun().callback({ exitCode = 2, stdout = "" })
    end
    if values.polling then callbacks[#callbacks]({ exitCode = 0, stdout = "{}" }) end

    -- A switch runs the CLI with the label as one argument, then re-reads both.
    before = #accountRuns
    local usageBefore = #callbacks
    now = now + 3000
    state.set("command", { action = "switch", label = "personal" })
    assert(#accountRuns == before + 1 and values.switching == "personal", "a switch should start and show")
    local switchRun = lastRun()
    assert(table.concat(switchRun.argv, " ") == "ai-usagebar account switch personal --cli",
        "the switch should be Claude CLI only")
    state.set("command", { action = "switch", label = "other" })
    assert(#accountRuns == before + 1, "a second switch waits for the first")
    now = now + 3000
    switchRun.callback({ exitCode = 0, stdout = "" })
    assert(values.switching == nil and values.switch_error == nil, "a good switch clears its state")
    assert(#accountRuns == before + 2 and table.concat(lastRun().argv, " ") == "ai-usagebar account status --json",
        "a switch should re-read the active account")
    assert(#callbacks == usageBefore + 1, "a switch should re-read usage")
    lastRun().callback({ exitCode = 0, stdout = "{}" })
    callbacks[#callbacks]({ exitCode = 0, stdout = "{}" })

    before = #accountRuns
    now = now + 3000
    env.onIpc("switch", "x; rm -rf ~")
    env.onIpc("switch", "")
    assert(#accountRuns == before, "labels that are not account names never reach the CLI")

    env.onIpc("switch", "personal")
    lastRun().callback({ exitCode = 1, stdout = "", stderr = "error: token=abc123 refused" })
    assert(values.switch_error.label == "personal", "a failed switch should name the account")
    assert(not values.switch_error.detail:find("abc123", 1, true), "switch errors are scrubbed")
end

io.write("ok: refresh queue coalesced, timeouts rejected, account status and switch\n")
