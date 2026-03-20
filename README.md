# TextFix

TextFix is a native Swift/AppKit macOS menu bar app that fixes selected text or rewrites it into a stronger prompt using either OpenAI or Anthropic.

## Install on macOS

1. Clone the repo:

```bash
git clone <REPO_URL>
cd textfixopenai
```

2. Build and install the app:

```bash
chmod +x build_app.sh install.sh
./install.sh
```

This builds `dist/TextFix.app` from the Swift package and installs it to `/Applications` when writable, otherwise `~/Applications`.

3. Open **Settings...** from the menu bar and add your API keys.
4. Grant Accessibility permissions and, if prompted, Input Monitoring.
5. Turn on **Open at login** if you want TextFix to start automatically.

## Run from source

Launch directly from SwiftPM:

```bash
swift run TextFix
```

The compiled debug executable lives under `.build/`.

## Build a standalone app bundle

```bash
./build_app.sh
open dist/TextFix.app
```

`build_app.sh` assembles a native app bundle at `dist/TextFix.app`.

To keep Accessibility permissions across updates, sign the app with a persistent identity and launch the installed copy from `/Applications` or `~/Applications`:

```bash
TEXTFIX_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./install.sh
open /Applications/TextFix.app
```

Without a real signing identity, macOS treats rebuilt bundles as a different app and may ask for Accessibility or Input Monitoring again.

## Tests

```bash
swift test
```

## Permissions

On first run, macOS will ask for Accessibility permissions. Enable **TextFix** in:

- System Settings > Privacy & Security > Accessibility
- System Settings > Privacy & Security > Input Monitoring, if macOS prompts for it

Then relaunch the app.

If macOS keeps asking after every rebuild, use `./install.sh` so the app stays at a fixed install path, and set `TEXTFIX_SIGN_IDENTITY` during build/install so the bundle keeps a stable code signature.

## Hotkeys and settings

Settings are stored at:

```text
~/Library/Application Support/TextFix/config.json
```

Defaults:

```text
Fix hotkey: <cmd>+<shift>+g
Prompt hotkey: <cmd>+<alt>+g
```

Menu actions:

- `Fix Selection`
- `Rewrite as Better Prompt`

You can update the model, prompts, temperature, max output tokens, notifications, and login-item behavior in the menu bar `Settings...` window. The config file stays in JSON so existing local installs can keep the same storage path.

## Project layout

- `Package.swift`: Swift package definition
- `Sources/TextFix`: native AppKit menu bar app
- `Sources/TextFixKit`: shared config, hotkey parsing, and API client logic
- `Packaging/Info.plist`: app bundle metadata used by `build_app.sh`

Legacy Python files are still present during the migration, but the maintained build and install path is now the Swift app above.
