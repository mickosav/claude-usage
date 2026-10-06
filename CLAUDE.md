# ClaudeUsage

A personal macOS menu bar app that mirrors the claude.ai usage page
(`https://claude.ai/new#settings/usage`). Built to replace ClaudeMeter, which
the user uninstalled because it did not surface reset times.

This is an unofficial tool: it reads claude.ai's internal endpoints using the
user's own session cookie. Anthropic could change or block these at any time.

## What it does

- Menu bar: two stacked monochrome progress bars (top = current session, bottom
  = weekly all-models) plus the session percentage as text.
- Click: a borderless panel below the icon showing Current session, Weekly "All
  models", and one row per model-scoped weekly limit (e.g. "Fable", "Sonnet";
  whatever the API returns), each with a bar, "% used", and reset time, plus a
  "Last updated / refresh" footer. Matches the claude.ai usage panel.

## Build and install

Requires the Swift toolchain (Command Line Tools is enough; no Xcode project).

```sh
cd app
./install.sh        # build + quit running app + copy to /Applications + ad-hoc sign + relaunch
./build.sh          # build only (-> build/ClaudeUsage.app), if you just want to compile
```

`install.sh` is the iteration loop: it calls `build.sh`, stops the running
instance, replaces `/Applications/ClaudeUsage.app`, re-signs, and relaunches.

- `build.sh` targets `${arch}-apple-macos13.0` and compiles with `-swift-version 5`
  (Swift 6 strict concurrency otherwise rejects the AppKit entry point).
- Signing is ad-hoc (`--sign -`). Fine for personal/local use; not distributable.
- Bundle id: `com.milutin.claudeusage`. `LSUIElement` is set, so no Dock icon.

## Session key (auth)

The app authenticates as the user via their claude.ai `sessionKey` cookie
(value starts with `sk-ant-sid...`). Stored in Keychain:
service `com.milutin.claudeusage`, account `sessionKey`.

Three ways to set it:
1. In-app: right-click the menu bar icon -> "Set session key...".
2. First launch with no key prompts for it automatically.
3. Seed from terminal (lets the app show data immediately):
   ```sh
   security add-generic-password -a sessionKey -s com.milutin.claudeusage -w "$SK" -A -U
   ```
   `-A` allows any app to read it without a Keychain prompt; `-U` updates if present.

To get the cookie: claude.ai -> DevTools -> Application -> Cookies ->
`https://claude.ai` -> `sessionKey` -> copy Value.

## Login item (start at login)

Right-click the menu bar icon -> "Start at login" (checkmark toggles state).
Uses `SMAppService.mainApp` (macOS 13+). Works best when the app lives in
`/Applications` and is launched from there.

From a terminal (same toggle; prints the state and exits without showing UI):
```sh
/Applications/ClaudeUsage.app/Contents/MacOS/ClaudeUsage --login-item=status   # or on|off
```
The registration is keyed by bundle id, so it survives `install.sh` replacing
the bundle and app relaunches. Verified 2026-10-07.

## Data source

- `GET https://claude.ai/api/organizations` -> array. Pick the org whose
  `capabilities` contains `"chat"` (fall back to first). `uuid` is the org id;
  `raven_type` (e.g. `team`) becomes the plan label, capitalized -> "Team".
- `GET https://claude.ai/api/organizations/{uuid}/usage` -> usage. Two shapes:
  - Legacy top-level keys: `five_hour`, `seven_day`, `seven_day_<model>` (e.g.
    `seven_day_sonnet`), each `{ utilization: 0-100, resets_at: ISO8601|null }`.
  - `limits[]` array (preferred, forward-compatible): each has `kind`
    (`session` / `weekly_all` / `weekly_scoped`), `percent`, `severity`,
    `resets_at`, and for scoped ones `scope.model.display_name` ("Fable",
    "Sonnet", ...). There can be several `weekly_scoped` entries; the panel
    shows all of them, titled by display name, in API order. Don't hardcode a
    model name anywhere in the parser or the UI.
  We read `limits[]` first and fall back to the legacy keys.
- Auth + headers: `Cookie: sessionKey=...` plus a Safari `User-Agent`, `Referer`,
  `Origin`, and `Sec-Fetch-*` headers to look like a browser request.

## Gotchas (read before debugging the network layer)

- Cloudflare blocks `curl`. A raw `curl` to these endpoints returns 403 "Just a
  moment..." because Cloudflare fingerprints the TLS handshake. `URLSession`
  (Apple's TLS stack) passes. Do NOT validate with curl. Use the probe tool:
  `cd app && SK='sk-ant-sid...' swift probe.swift` prints the org list and raw usage JSON.
- Invalid key vs Cloudflare block, both return 403. A rejected session key
  returns 403 with a JSON body containing `account_session_invalid` /
  "Invalid authorization"; a Cloudflare block returns 403 as HTML. Only the JSON
  case maps to `UsageError.unauthorized` -> "Session expired" screen. Other 403s
  are treated as transient and retried.
- `resets_at` has 6-digit microseconds. `ISO8601DateFormatter` with fractional
  seconds can fail on it; `UsageClient.parseDate` trims to milliseconds as a
  fallback.
- `resets_at` lands just before the boundary (e.g. `04:59:59.999`). claude.ai
  rounds to the minute ("Resets Tue 5:00 AM", "Resets in 3 hr 7 min"). The
  formatters in `PopoverView` round the same way: weekly times round to the
  nearest minute, the session countdown rounds minutes up. Truncating instead
  showed "4:59 AM" and ran one minute behind the web page.
- ExFAT breaks `codesign`. This repo lives on `/Volumes/PortableSSD`, which is
  ExFAT and has no native extended attributes, so macOS spills them into
  AppleDouble `._` sidecar files. `codesign` then fails with "Operation not
  permitted / In subcomponent: ...._MacOS". `build.sh` therefore assembles and
  signs under `TMPDIR` (internal APFS) and `ditto`s the result into `build/`;
  `install.sh` runs `dot_clean -m` on `/Applications/ClaudeUsage.app` before
  re-signing. Don't move the signing step back in-tree.
- Background `Bash` calls do not keep the working directory. Use absolute paths
  when building from a backgrounded shell.
- Keychain scanning (`security find-generic-password` / `dump-keychain` to
  discover tokens) is blocked by the safety classifier. Set keys explicitly with
  the `add-generic-password` command above instead.
- The agent shell cannot take screenshots (no Screen Recording permission).
  Visual changes must be verified by the user.

## Design decisions (do not undo without asking)

- Menu bar icon is a monochrome template image. No color. Bars dim to 50% alpha
  when data is stale/offline. Metrics in `StatusItemRenderer`: barWidth 44,
  barHeight 5, gap 2, corner radius 1.5, minNub 2. Wider track + small nub were
  chosen so session vs weekly read proportionally at small percentages.
- The percentage shown in the menu bar is the current session value.
- The panel is a borderless rounded `NSPanel` positioned below the icon
  (`UsagePanel`), NOT an `NSPopover`. The user explicitly did not want the
  popover arrow.
- The panel body keeps blue bars (the user approved that look). The "Learn more
  about usage limits" link was removed.
- Refresh cadence: default 5 min; options Off / 2 / 5 / 15 / 30 min. No 30s or
  1 min option. Rationale: usage moves slowly (5h session, 7d weekly) and
  claude.ai itself does not poll while its panel is open, so frequent polling
  adds rate-limit risk for no visible benefit.
- Refresh-on-open only fires if data is older than 60s; otherwise show cache.
- Manual refresh: immediate fetch, spinner + disabled while in-flight, 3s
  debounce, resets the auto-poll timer on success.
- "Last updated" buckets: "just now" (<10s), "less than a minute ago" (<60s),
  "N min ago", "N hr ago", "Updated at HH:mm" (>=24h). Age is computed from the
  real clock at render time and clamped with `max(0, ...)`. The clamp fixes a
  bug where a stale UI clock made the label read a future time ("in 7 seconds").
- Offline (`NWPathMonitor`): suppress auto-poll, footer reads "Offline ...",
  fetch once on reconnect. Stale (failed refresh with last-good data): keep the
  data dimmed, orange footer "Couldn't refresh ...". Session expired: dedicated
  screen with "Update session key..." and an "Open claude.ai" link.

## Files

- `app/Sources/main.swift` - entry point (`MainActor.assumeIsolated`, accessory policy)
- `app/Sources/AppDelegate.swift` - status item, panel wiring, auto-poll timer, right-click menu, login item
- `app/Sources/UsageClient.swift` - networking, JSON parsing, models, date parsing
- `app/Sources/UsageStore.swift` - `ObservableObject` state, NWPathMonitor, debounce, freshness, auth detection
- `app/Sources/Keychain.swift` - session key load/save/clear
- `app/Sources/StatusItemRenderer.swift` - menu bar two-bar template image
- `app/Sources/PopoverView.swift` - SwiftUI panel content + formatting
- `app/Sources/UsagePanel.swift` - borderless rounded panel (no arrow)
- `app/Sources/SessionKeyPrompt.swift` - NSAlert key entry
- `app/Info.plist` - bundle config (LSUIElement)
- `app/build.sh` - compile + bundle + ad-hoc sign
- `app/install.sh` - build + install to /Applications + relaunch (the iteration loop)
- `app/probe.swift` - standalone debug tool; inspects raw API responses via URLSession (not part of the build)
