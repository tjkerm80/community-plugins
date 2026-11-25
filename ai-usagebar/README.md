# AI Usage

Track AI plan usage, quota resets, and consumption pace in the Noctalia bar.

The numbers come from [ai-usagebar](https://github.com/akitaonrails/ai-usagebar),
a Rust CLI that reads Claude, Codex, GitHub Copilot, Cursor, Antigravity, Kiro,
Z.AI, Nous Research, OpenCode Go, Command Code, OpenRouter, DeepSeek, Kimi and Grok, among
others. The selector also includes DeepInfra, Grok Bot, Ollama Cloud, OrcaRouter,
Model Studio, Lyceum, Devin, Cline, Muse Code, Synthetic, Droid, DeepRelay and Mistral. The plugin runs
`ai-usagebar usage --json` and `ai-usagebar account status --json` and displays
the report and the active Claude account. Diagnostics reads the provider catalog
with `ai-usagebar vendors --json` on demand, and a switch button runs
`ai-usagebar account switch <label> --cli`. The plugin does not call provider
APIs or read credential files.

The account commands need an `ai-usagebar` build that has the `account`
subcommand. With an older CLI the bar falls back to the default Claude login and
the switch buttons report a failure.

## Plugin

| Field | Value |
| --- | --- |
| ID | `felipeartur/ai-usagebar` |
| Entries | Bar widget: `bar`; panel: `panel`; service: `poller` |

## Requirements

Install `ai-usagebar` on `PATH`. The plugin runs it by name and has no separate
path setting. It ships as `ai-usagebar-bin` on the AUR, and as release
tarballs on the project's GitHub Releases page. Configure your providers once in
`~/.config/ai-usagebar/config.toml`; the CLI manages credentials and provider
connections.

The plugin accepts the optional fields through ai-usagebar 1.52.0, including
Antigravity model pools and Synthetic refill metadata. Older CLI reports remain supported; a
provider appears only when the installed CLI can report it. Mistral budgets and
Kimi monthly-only plans use only the windows supplied by the CLI; calendar
budgets without a fixed duration do not get an elapsed-time gauge. Since 1.40.1, the CLI
may run `agy -p "/quota" --output-format json` when `agy` is installed to read
Antigravity quotas. The plugin does not start or configure `agy` itself.

The CLI sends quota notifications according to its own settings. The plugin
adds no alerts or extra thresholds. To
disable them, add this to `~/.config/ai-usagebar/config.toml`:

```toml
[notifications]
enabled = false
```

When the CLI is missing, the panel displays its project address and can open it
with `xdg-open`. The same command opens provider dashboards from the panel.
Install `xdg-open` alongside `ai-usagebar`.

The plugin requires plugin API 43 for the current Noctalia palette roles,
container tooltips and shared modules.
It will not install on an older shell. Plugin version 1.1.0 remains available for API 9.

Text follows the shell's typography and the configured font family, weight and
font scale. Provider marks use a 16px glyph in an 18px slot.

## Usage

Add `felipeartur/ai-usagebar:bar` to a bar in Settings, Bar. The capsule shows
the active Claude account: the account named by `ai-usagebar account status`, or
the default `anthropic` login when no named account matches. It draws two pills
side by side, the 5-hour session and the overall weekly quota (`Weekly (7d)`,
not a model pool such as `Fable (7d)`), each followed by its percentage.

- A vertical tick on each pill marks how much of the window has elapsed. When
  usage is ahead of the tick, the fill changes from `primary` to the theme's
  `secondary` warning color.
- An account with no 5-hour limit reports no session window. Its session pill is
  drawn as an outline with no fill and no tick, labelled `∞`. A real 0% keeps
  the solid track, the tick and `0%`.
- The provider icon turns to the `error` color when a read fails; the last
  numbers stay. A clock icon marks a stale reading.
- Hover shows the account, each window's percentage and elapsed time, and a
  separate row with when each window resets: the countdown and the clock time.
- Left click opens the panel at the active account. **Open panel in** chooses
  whether that is All accounts or the account's details.
- Right click requests a refresh. One poller serves every capsule and keeps at
  most one pending refresh when requests arrive during a read.
- Middle click opens the widget's settings, as everywhere else in the shell.

The ticks move with the clock, so the capsule redraws every 30 seconds without
running the CLI.

The script handles left click; the shell opens settings on middle click.
Right click is a gesture binding in the widget settings, where you can assign
another action or choose `none`.

With multiple accounts, a direct panel open starts with **All accounts**: every
account on one scrolling list of compact cards. Cards are ordered as follows:

1. the active Claude account;
2. accounts with usage left in both the session and the overall weekly window
   (a full model pool such as `Fable (7d)` does not count);
3. everything else.

Within each group, the account whose weekly quota resets soonest comes first.
The bare `anthropic` entry is hidden when named Claude accounts exist, because
it repeats the active one.

A card with session or weekly windows shows the same pills as the bar, with
percentages and reset countdowns. Other providers show their first two readings
or their balance. Each reset credit the CLI reports gets its own line on the
card, with its title and the time left before it expires. Each card also shows
read failures, reading age and stale status.

Every inactive Claude account has a **Switch** button. It runs
`ai-usagebar account switch <label> --cli` at once, with no confirmation, then
reads the account status and usage again. The buttons are disabled while a
switch runs, and a failure is shown on that account's card. An account whose
5-hour or overall weekly window is at 100% can only run on extra usage. When
its `Extra usage` metric (the monthly pay-as-you-go cap) is under 100%, the
button stays enabled and shows a coin glyph instead of the switch arrows.
Otherwise it is disabled. A full model pool such as Fable does not count
toward the limit. The active account
is marked **Active**. Other providers have no switch button.

Click a card to see its windows, models, credits and optional priorities.
**All accounts** returns to the overview without changing the CLI's active
account. With one account, the panel opens directly in its details.

The detail tabs identify the selected account. Up to five account tabs remain
visible; previous/next controls handle longer lists. Compact tabs
reveal full names on hover. Session and weekly limits share a card; Antigravity
has a separate card for each model. Each window shows its quota bar, a short
reset countdown and consumption pace. For Antigravity, pace is estimated from
usage, window duration and reset time; it is hidden if those values are unavailable
or the reset has passed.
Hover the countdown for the local reset time. A thinner bar compares quota with
reported window time: elapsed in used mode, time left in remaining mode.
Hover the window label for its time percentage. The thin bar stays hidden when
the CLI supplies no window time.
The shared `Claude & GPT OSS` quota keeps the name supplied by the CLI.

The footer shows the update time and up to two quota warnings above 50% usage,
with the most restrictive window per model. A `+N` indicates additional warnings.
Hover a pill for its full status. Exhausted quotas also show their reset countdown.
Read failures show the last known state. The panel displays quota readings,
not agent process health.

The header stays fixed while reports scroll. The reading viewport adapts to the
amount of data within a 640px panel maximum; scrolling keeps long reports
accessible. Cards reserve space for the scrollbar so their width stays the same
between providers.

Opening the panel requests fresh data. The header keeps refresh and close within
reach, alongside diagnostics and settings. The account footer offers Copy summary
and the provider dashboard. Both Antigravity model groups share the same service link. Click outside, click the widget again or press Escape to close
the panel. Press R to refresh usage, or both usage and the catalog while Diagnostics is open.
Arrow keys select accounts outside Diagnostics. In the overview they reveal the
selected card; Enter opens its detail. Press O to return to All accounts.

The list contains providers with usable readings and parser failures. A default
provider reporting no API key is hidden because the CLI does not distinguish
a missing credential from a provider that was never configured. A configured
provider with its own refresh failure also leaves the bar and panel, then
returns automatically after a healthy read. If the CLI instead supplies a dated,
ready cache, its last quota or balance stays visible as stale, including after
a rejected API-key request. Diagnostics retains the reported failure and recovery guidance.

An empty report shows a message and a direct Diagnostics action. A failed refresh
without a visible reading shows the error and retry action instead of a stale-data notice.

Model-specific Gemini pools, such as
Gemini 4 Argon, appear inside the Gemini card with their own name, reset and usage. They do not add a separate bar reading.
A full Gemini 4 Argon pool does not mark Antigravity as
exhausted while its shared windows remain available. The detail tabs follow the
same order as the All accounts list.

Antigravity is the exception when its local server briefly disappears: the last
reading stays visible with a stale indicator and its original update time until
the server returns. Without an earlier reading, it stays unavailable.

Parser errors are an exception: the provider remains visible with missing usage
and the CLI error, because a response-format failure does not establish that the
account is unavailable.

Details include the account name, reading age, stale status, window labels, percentages, elapsed time, reset countdowns and local reset times, pace,
and high or critical severity labels. Raw values appear when they add information
to the percentage. Credit blocks and free text are also shown; zero credit
balances are hidden. Codex reset credits show the reset type and expiry on
separate lines, with wrapping for longer descriptions.

Cursor On-Demand spending has its own meter when the CLI reports a positive cap
and percentage. Its currency amount stays visible; used/remaining does not invert
spending. An uncapped amount stays text. Synthetic shows the subscription quota
and request count supplied by the CLI, without assuming a reset window. A metric
with `reading = "left"` always shows its remaining quota, even in used mode.
Printed figures honor `percent_precise` (up to two decimal places); meters and
severity retain the integer `percent`. When `regen` is present, the panel and
bar tooltip describe the next partial refill, such as "Regenerates 2% in 2h",
instead of a full reset. Countdown values tick locally from `reset_at`.
Droid and DeepRelay use the same report contract; selecting them does not enable
or authenticate them in the CLI.

A whole-report failure is different: it cannot identify one broken provider,
so it keeps the last list and marks those readings as old instead of blanking
the panel during a network interruption.

To open the panel from a terminal:

```sh
noctalia msg panel-toggle felipeartur/ai-usagebar:panel
```

## Priorities

![Model quota card with account priorities, using example data](images/priorities.png)

Turn on **Show priorities** in the plugin settings to show the estimates inside
each existing model card, alongside its quota windows. The service then runs
`ai-usagebar usage --json --priorities`. This requires ai-usagebar 1.46 or newer
and is off by default.

The details follow the selected account: reported status, projected unused
quota, remaining quota and reset countdown when available. The CLI's suggestion
is marked separately. For providers that group several models in one account,
the section is labelled **Account priorities** because the CLI supplies an
account estimate. It does not calculate a separate projection for each model.

The ordinary provider tabs, refresh action and keyboard navigation remain in
place. Old or expired suggestions are labelled and need a fresh report before
an account can be suggested again. The bar always shows the active Claude
account.

While enabled, the CLI records a small local history of quota percentages and
timestamps. Turning the option off hides the embedded details and stops
requesting this mode. Existing CLI history stays in place. The plugin keeps no
separate history. If the CLI rejects the flag, polling falls back to the ordinary
command and the embedded section explains the missing support.

## Settings

Plugin-level, shared by the poller, every capsule and the panel:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_priorities` | `bool` | `false` | Show priority estimates inside the model cards. Records quota history locally while enabled. |
| `refresh_minutes` | `int` | `5` | Minutes between quota calls, from 1 to 120. Countdowns tick locally in between. |
| `usage_display` | `select` | `used` | Show `used` or `remaining` quota in every capsule and the panel. Numbers and gauges change together; colors and priority still follow consumption. Balances are unchanged. |

Per widget instance:

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_glyph` | `bool` | `true` | Show the provider's icon before the pills. |
| `panel_view` | `select` | `overview` | Open All accounts or the active account's details. An empty capsule opens All accounts. |

## Diagnostics

Open Diagnostics from the panel header when a configured provider is missing or
shows an old reading. Each problem shows a status and a suggested next step. Named
account failures retain the account label. Open **Details** to see a technical
cause. Provider lists are omitted from this view.

Opening Diagnostics reads the local provider catalog. **Refresh** requests both
the catalog and usage through the shared poller. The view never signs in, changes
configuration or executes commands from the response. If the CLI does not support
`vendors --json` (available since 1.13.0), the catalog remains unavailable; known
failures from the usage report can still appear.

The existing IPC context opens Diagnostics directly:

```sh
noctalia msg panel-open felipeartur/ai-usagebar:panel setup
```

### Antigravity disappears with HTTP 401/403

First check the official CLI with `agy -p /quota`. A rejected local Antigravity
RPC does not establish that the Google login or quota is unavailable. For example,
AGY 1.5.7 can answer its quota command successfully while its local RPC answers
plain-text `401 Unauthorized`; ai-usagebar 1.51.0 recognizes a narrower JSON
missing-CSRF response before using its fallback.

If the quota command works, investigate the collector's local-server integration.
If it also fails, check the Antigravity login. The plugin does not rewrite
credentials or turn a rejected report into a zero or a fresh cached quota.
An unavailable provider remains documented in Diagnostics.

## IPC

Open the multi-account overview explicitly. With only one available account,
the panel opens its details instead:

```sh
noctalia msg panel-open felipeartur/ai-usagebar:panel overview
```

Force a refresh without waiting for the interval:

```sh
noctalia msg plugin felipeartur/ai-usagebar:poller all refresh
```

Point the panel at a provider, by the id `ai-usagebar` uses for it:

```sh
noctalia msg plugin felipeartur/ai-usagebar:poller all select anthropic
```

Make a named Claude account the `claude` CLI's login, as the panel's switch
button does. A label is up to 64 letters, digits, `.`, `_` and `-`, starting
with a letter or digit:

```sh
noctalia msg plugin felipeartur/ai-usagebar:poller all switch work
```

Request a provider catalog read without polling quotas:

```sh
noctalia msg plugin felipeartur/ai-usagebar:poller all catalog
```

## Notes

Tooltips use the shell's native appearance, timing and position. They do not
capture pointer clicks or keyboard focus. Panel tips stay on small controls and
labels; long technical details require an explicit click inside Diagnostics.

- One process, `ai-usagebar usage --json`, spawned by a single headless service
  on the configured interval, plus on demand from a right click, from opening
  the panel, or from the IPC event above. Capsules and the panel are subscribers
  of plugin state, so a second monitor or a second capsule costs no extra
  process. Enabling priorities adds `--priorities` to that same process.
- Each poll also runs `ai-usagebar account status --json` to learn the active
  Claude account. Only the account label is published to plugin state; the
  email addresses in that output are not.
- A switch runs `ai-usagebar account switch <label> --cli` with a 30-second
  timeout, one switch at a time. The label is validated and passed as an
  argument list, not through a shell.
- Diagnostics adds a separate `ai-usagebar vendors --json` process on demand,
  with a five-second timeout and one query in flight. It contacts no provider
  endpoint. The CLI may enforce restrictive permissions on its own configuration
  file when loading it, as it does for quota reads.
- Custom providers can use a known brand icon supplied by the CLI. Unknown brands
  use the provider fallback. Brand metadata never chooses a dashboard URL.
- The plugin makes no network calls and writes no files of its own; a switch
  changes the CLI's login through the CLI. Everything it knows arrives on those
  commands' stdout. Catalog state retains only provider
  names, IDs and configuration flags, without login commands or environment fields.
- A failed whole-report read keeps the previous report and marks it as stale.
  Without a previous report, the panel shows the failure and its scrubbed
  diagnostic. Raw HTTP details stay out of the reading cards.
- CLI documents are limited to 1 MiB, 32 structural levels and 20,000 value nodes
  before scrubbing or publication. Usage reports support up to 128 accounts. The byte limit applies before JSON decoding;
  structural limits apply after decoding. Rejected reports retain the previous
  reading and allow another refresh. Diagnostics applies the same limits to its
  catalog and retains the previous catalog on failure.
- Report text is scrubbed for common credential patterns before publication to
  plugin state. This is a precaution, not a guarantee that arbitrary CLI output
  contains no sensitive data. Review account labels and diagnostics before
  sharing screenshots.

## Tests

Run the tests from the `ai-usagebar` directory:

```sh
TZ=America/New_York lua tests/scrub_test.lua
TZ=America/New_York lua tests/refresh_test.lua
TZ=America/New_York lua tests/bar_test.lua
TZ=America/New_York lua tests/panel_test.lua
TZ=America/New_York lua tests/shared_test.lua
TZ=America/New_York lua tests/catalog_test.lua
```

The suites cover secret redaction and its callback CPU budget, refresh scheduling,
the active-account read and account switching, the bar's quota pills and ticks,
the account order and switch buttons in the panel, optional priorities,
timestamps, on-demand diagnostics and excessive reports.
They use synthetic reports; they do not read credentials
or call provider APIs. UI trees are checked in a test host, without rendering the
native shell.
