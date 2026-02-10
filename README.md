# TextFix

## Install (MVP)

### Option A — Prebuilt app (recommended)

1. Download the latest `TextFix.zip` from GitHub Releases.
2. Unzip it, then move `TextFix.app` to `/Applications`.
3. First run: right-click the app and choose **Open** (macOS Gatekeeper).
4. Grant Accessibility (and Input Monitoring if prompted).
5. Open **Settings...** from the menu bar and paste your API keys.

### Option B — Run from source

1. Clone the repo and install dependencies:

```bash
git clone <REPO_URL>
cd textfixopenai
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Run the app:

```bash
python textfix_app.py
```

3. Open **Settings...** from the menu bar and paste your API keys.

A lightweight macOS menu bar app that fixes spelling and grammar for selected text using a cloud API. Select text, press the hotkey, and the corrected text is pasted back in place.

## Setup (Run from Source)

1. Create a virtual environment and install dependencies:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

2. Set your API keys inside the app via the menu bar `Settings...` window.

3. Run the app:

```bash
python textfix_app.py
```

## Tests

Ensure dependencies are installed (see Setup), then run:

```bash
python -m unittest discover -s tests
```

## Permissions

On first run, macOS will ask for Accessibility permissions (and sometimes Input Monitoring). Enable **TextFix** in:

- System Settings > Privacy & Security > Accessibility
- System Settings > Privacy & Security > Input Monitoring (if prompted)

Then relaunch the app.

## Hotkey and Settings

Settings are stored at:

```
~/Library/Application Support/TextFix/config.json
```

Default hotkey is:

```
<cmd>+<shift>+g
```

You can update `model`, `system_prompt`, `temperature`, `max_output_tokens`, or `show_notifications` in the config file. Most settings (including hotkey, model, and prompt) are also available via the menu bar `Settings...` window.

In the hotkey field, click and press the keys you want (for example, `Cmd+Shift+G`). The field will capture the combination automatically.

## Build a Standalone .app

```bash
pip install py2app
python setup.py py2app
open dist/TextFix.app
```

If you want the app to start at login, add `TextFix.app` to your Login Items in System Settings.

API keys are stored locally in the user config file at:

```
~/Library/Application Support/TextFix/config.json
```
