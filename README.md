# ClaudeUsage

A small macOS menu bar app that mirrors the claude.ai usage page.

- **Menu bar:** two stacked monochrome bars — top is the current 5-hour session,
  bottom is the weekly all-models limit — plus the session percentage as text.
- **Click:** a panel showing Current session, Weekly "All models" and "Sonnet
  only", each with a bar, "% used" and a reset time, plus a refresh footer.

## Unofficial

This is not an Anthropic product. It reads claude.ai's internal endpoints using
your own session cookie, and Anthropic can change or block them at any time. Use
it on your own account only.

## Build

Requires the Swift toolchain (Command Line Tools is enough — there's no Xcode
project).

```sh
cd app
./install.sh   # build, install to /Applications, relaunch
./build.sh     # build only, to build/ClaudeUsage.app
```

Signing is ad-hoc, which is fine for local use but means the app is not
distributable as-is.

## Session key

The app authenticates with your claude.ai `sessionKey` cookie, stored in the
Keychain (service `com.milutin.claudeusage`, account `sessionKey`). It is never
written to source or to disk in plaintext.

Set it either from the app — right-click the menu bar icon → "Set session
key…", or the prompt shown on first launch — or from the terminal:

```sh
security add-generic-password -a sessionKey -s com.milutin.claudeusage -w "$SK" -A -U
```

To find the cookie: claude.ai → DevTools → Application → Cookies →
`https://claude.ai` → `sessionKey` → copy the value.

## Start at login

Right-click the menu bar icon → "Start at login", or add
`/Applications/ClaudeUsage.app` under System Settings → General → Login Items &
Extensions.

## License

MIT
