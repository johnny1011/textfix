import json
import os
import plistlib
import subprocess
import sys
import threading
import time
from pathlib import Path

import objc
import rumps
from PyObjCTools import AppHelper
from textfix_core import rewrite_text, rewrite_text_anthropic
from AppKit import (
    NSAlert,
    NSApp,
    NSButton,
    NSMakeRect,
    NSMenu,
    NSMenuItem,
    NSPasteboard,
    NSPasteboardTypeString,
    NSPopUpButton,
    NSScrollView,
    NSSecureTextField,
    NSSwitch,
    NSTextField,
    NSTextView,
    NSView,
    NSEventModifierFlagCommand,
    NSEventModifierFlagControl,
    NSEventModifierFlagOption,
    NSEventModifierFlagShift,
)
try:
    from Quartz import AXIsProcessTrustedWithOptions, kAXTrustedCheckOptionPrompt
except ImportError:
    from ApplicationServices import AXIsProcessTrustedWithOptions, kAXTrustedCheckOptionPrompt
from Quartz import (
    CGEventCreateKeyboardEvent,
    CGEventGetFlags,
    CGEventGetIntegerValueField,
    CGEventPost,
    CGEventSetFlags,
    CGEventTapCreate,
    CGEventTapEnable,
    kCGEventFlagMaskAlternate,
    kCGEventFlagMaskCommand,
    kCGEventFlagMaskControl,
    kCGEventFlagMaskShift,
    kCGEventKeyDown,
    kCGEventTapOptionListenOnly,
    kCGHeadInsertEventTap,
    kCGHIDEventTap,
    kCGKeyboardEventKeycode,
)
from CoreFoundation import (
    CFMachPortCreateRunLoopSource,
    CFRunLoopAddSource,
    CFRunLoopGetMain,
    kCFRunLoopCommonModes,
)

APP_NAME = "TextFix"
CONFIG_DIR = Path.home() / "Library/Application Support/TextFix"
CONFIG_PATH = CONFIG_DIR / "config.json"
OPENAI_MODEL_CHOICES = ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
ANTHROPIC_MODEL_CHOICES = [
    "claude-opus-4-6",
    "claude-opus-4-5-20251101",
    "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001",
]
MODEL_CHOICES = OPENAI_MODEL_CHOICES + ANTHROPIC_MODEL_CHOICES
INLINE_SPINNER_PREFIX = "⏳"
COPY_POLL_INTERVAL = 0.02
COPY_POLL_ATTEMPTS = 25
HOTKEY_MODIFIER_MASK = (
    kCGEventFlagMaskCommand
    | kCGEventFlagMaskShift
    | kCGEventFlagMaskAlternate
    | kCGEventFlagMaskControl
)

DEFAULT_CONFIG = {
    "openai_api_key": "",
    "anthropic_api_key": "",
    "hotkey": "<cmd>+<shift>+g",
    "prompt_hotkey": "<cmd>+<option>+g",
    "model": "gpt-4.1-mini",
    "temperature": 0.0,
    "max_output_tokens": 512,
    "open_at_login": False,
    "show_notifications": False,
    "system_prompt": (
        "You are a copyeditor. Fix spelling, grammar, and punctuation while "
        "preserving the original meaning and tone. Return only the corrected text."
    ),
    "prompt_system_prompt": (
        "You are a prompt engineer and copyeditor. Rewrite the user's text into a single, "
        "clear, high-quality prompt. Fix spelling, grammar, and punctuation. Preserve the "
        "original intent and important constraints. Return only the rewritten prompt."
    ),
}


def load_config():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_PATH.exists():
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG.copy()

    try:
        with CONFIG_PATH.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        data = {}

    updated = False
    for key, value in DEFAULT_CONFIG.items():
        if key not in data:
            data[key] = value
            updated = True

    if data.get("api_key") and not data.get("openai_api_key"):
        data["openai_api_key"] = data["api_key"]
        updated = True
    if "api_key" in data:
        data.pop("api_key", None)
        updated = True

    if updated:
        save_config(data)

    return data


def save_config(config):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with CONFIG_PATH.open("w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, sort_keys=True)
        f.write("\n")


SPECIAL_KEYCODES = {
    36: "enter",
    48: "tab",
    49: "space",
    51: "backspace",
    53: "esc",
    117: "delete",
    123: "left",
    124: "right",
    125: "down",
    126: "up",
    115: "home",
    119: "end",
    116: "pageup",
    121: "pagedown",
    122: "f1",
    120: "f2",
    99: "f3",
    118: "f4",
    96: "f5",
    97: "f6",
    98: "f7",
    100: "f8",
    101: "f9",
    109: "f10",
    103: "f11",
    111: "f12",
    105: "f13",
    107: "f14",
    113: "f15",
    106: "f16",
    64: "f17",
    79: "f18",
    80: "f19",
    90: "f20",
}

def format_hotkey_event(event):
    flags = event.modifierFlags()
    parts = []
    if flags & NSEventModifierFlagCommand:
        parts.append("<cmd>")
    if flags & NSEventModifierFlagControl:
        parts.append("<ctrl>")
    if flags & NSEventModifierFlagOption:
        parts.append("<alt>")
    if flags & NSEventModifierFlagShift:
        parts.append("<shift>")

    key_name = event.charactersIgnoringModifiers() or ""
    key_code = event.keyCode()
    special = SPECIAL_KEYCODES.get(key_code)
    if special:
        if special == "backspace":
            return ""
        key_token = f"<{special}>"
    else:
        if not key_name:
            return None
        char = key_name[0].lower()
        if char == "\r":
            key_token = "<enter>"
        elif char == "\t":
            key_token = "<tab>"
        elif char == " ":
            key_token = "<space>"
        else:
            key_token = char

    if not parts:
        return key_token
    return "+".join(parts + [key_token])


KEYCODE_MAP = {
    "a": 0,
    "s": 1,
    "d": 2,
    "f": 3,
    "h": 4,
    "g": 5,
    "z": 6,
    "x": 7,
    "c": 8,
    "v": 9,
    "b": 11,
    "q": 12,
    "w": 13,
    "e": 14,
    "r": 15,
    "y": 16,
    "t": 17,
    "1": 18,
    "2": 19,
    "3": 20,
    "4": 21,
    "6": 22,
    "5": 23,
    "=": 24,
    "9": 25,
    "7": 26,
    "-": 27,
    "8": 28,
    "0": 29,
    "]": 30,
    "o": 31,
    "u": 32,
    "[": 33,
    "i": 34,
    "p": 35,
    "l": 37,
    "j": 38,
    "'": 39,
    "k": 40,
    ";": 41,
    "\\": 42,
    ",": 43,
    "/": 44,
    "n": 45,
    "m": 46,
    ".": 47,
    "`": 50,
    "space": 49,
    "tab": 48,
    "enter": 36,
    "esc": 53,
    "backspace": 51,
    "delete": 117,
    "left": 123,
    "right": 124,
    "down": 125,
    "up": 126,
}


def parse_hotkey(hotkey):
    parts = [p.strip() for p in hotkey.split("+") if p.strip()]
    modifiers = 0
    keycode = None
    modifier_map = {
        "cmd": kCGEventFlagMaskCommand,
        "command": kCGEventFlagMaskCommand,
        "shift": kCGEventFlagMaskShift,
        "alt": kCGEventFlagMaskAlternate,
        "option": kCGEventFlagMaskAlternate,
        "ctrl": kCGEventFlagMaskControl,
        "control": kCGEventFlagMaskControl,
    }

    for part in parts:
        token = part.lower()
        if token.startswith("<") and token.endswith(">"):
            token = token[1:-1]
        if token in modifier_map:
            modifiers |= modifier_map[token]
        else:
            keycode = KEYCODE_MAP.get(token)
            if keycode is None and len(token) == 1:
                keycode = KEYCODE_MAP.get(token)

    if keycode is None:
        return None
    return {"keycode": keycode, "modifiers": modifiers}


def hotkey_matches_event(spec, keycode, flags):
    if not spec:
        return False
    if keycode != spec["keycode"]:
        return False
    return (flags & HOTKEY_MODIFIER_MASK) == spec["modifiers"]


class HotkeyCaptureView(NSView):
    def initWithFrame_(self, frame):
        self = objc.super(HotkeyCaptureView, self).initWithFrame_(frame)
        if self is None:
            return None
        self.display = NSTextField.alloc().initWithFrame_(
            NSMakeRect(0, 0, frame.size.width, frame.size.height)
        )
        self.display.setBezeled_(True)
        self.display.setEditable_(False)
        self.display.setSelectable_(False)
        self.display.setDrawsBackground_(True)
        self.display.setStringValue_("")
        self.addSubview_(self.display)
        return self

    def acceptsFirstResponder(self):
        return True

    def mouseDown_(self, event):
        if self.window():
            self.window().makeFirstResponder_(self)
        objc.super(HotkeyCaptureView, self).mouseDown_(event)

    def keyDown_(self, event):
        hotkey = format_hotkey_event(event)
        if hotkey is None:
            return
        self.setStringValue_(hotkey)

    def setStringValue_(self, value):
        self.display.setStringValue_(value)

    def stringValue(self):
        return self.display.stringValue()

    def setPlaceholderString_(self, value):
        self.display.setPlaceholderString_(value)


def _handle_edit_shortcut(responder, event):
    if not (event.modifierFlags() & NSEventModifierFlagCommand):
        return False
    key = (event.charactersIgnoringModifiers() or "").lower()
    if key == "v":
        responder.paste_(None)
        return True
    if key == "c":
        responder.copy_(None)
        return True
    if key == "x":
        responder.cut_(None)
        return True
    if key == "a":
        responder.selectAll_(None)
        return True
    return False


class PasteableTextField(NSTextField):
    def keyDown_(self, event):
        if _handle_edit_shortcut(self, event):
            return
        objc.super(PasteableTextField, self).keyDown_(event)


class PasteableSecureTextField(NSSecureTextField):
    def keyDown_(self, event):
        if _handle_edit_shortcut(self, event):
            return
        objc.super(PasteableSecureTextField, self).keyDown_(event)


class TextFixApp(rumps.App):
    def __init__(self):
        super().__init__(APP_NAME, title="Aa", quit_button=None)
        rumps.events.before_start(self._schedule_ui_setup)
        self.config = load_config()
        self.hotkey_spec = parse_hotkey(self.config["hotkey"]) or parse_hotkey(
            DEFAULT_CONFIG["hotkey"]
        )
        self.prompt_hotkey_spec = parse_hotkey(self.config["prompt_hotkey"]) or parse_hotkey(
            DEFAULT_CONFIG["prompt_hotkey"]
        )
        self._run_lock = threading.Lock()
        self._hotkey_tap = None
        self._hotkey_tap_callback = None
        self._hotkey_source = None
        self._setup_hotkey_tap()
        self._ensure_accessibility()
        self._apply_login_item(self.config.get("open_at_login", False))

    def _schedule_ui_setup(self):
        AppHelper.callAfter(self._finish_ui_setup)

    def _finish_ui_setup(self):
        self._ensure_edit_menu()
        self.menu.clear()
        self.menu.update(
            [
                "Fix Selection",
                "Rewrite as Better Prompt",
                None,
                "Settings...",
                "Open Config Folder",
                None,
                "Quit",
            ]
        )
        self.menu["Fix Selection"].set_callback(self.fix_selection_clicked)
        self.menu["Rewrite as Better Prompt"].set_callback(self.rewrite_prompt_clicked)
        self.menu["Settings..."].set_callback(self.settings_clicked)
        self.menu["Open Config Folder"].set_callback(self.open_config_folder)
        self.menu["Quit"].set_callback(self.quit_app)

    def _ensure_edit_menu(self):
        main_menu = NSApp.mainMenu()
        if main_menu is None:
            main_menu = NSMenu.alloc().initWithTitle_("MainMenu")
            NSApp.setMainMenu_(main_menu)
            app_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("", None, "")
            main_menu.addItem_(app_item)
            app_menu = NSMenu.alloc().initWithTitle_(APP_NAME)
            app_item.setSubmenu_(app_menu)
            quit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                f"Quit {APP_NAME}",
                "terminate:",
                "q",
            )
            app_menu.addItem_(quit_item)

        for item in main_menu.itemArray() or []:
            if item.title() == "Edit":
                return

        edit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Edit", None, "")
        main_menu.addItem_(edit_item)
        edit_menu = NSMenu.alloc().initWithTitle_("Edit")
        edit_item.setSubmenu_(edit_menu)
        for title, action, key in (
            ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a"),
        ):
            menu_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(title, action, key)
            edit_menu.addItem_(menu_item)

    def on_hotkey(self):
        self._run_action("fix")

    def on_prompt_hotkey(self):
        self._run_action("prompt")

    def fix_selection_clicked(self, _):
        self.on_hotkey()

    def rewrite_prompt_clicked(self, _):
        self.on_prompt_hotkey()

    def _run_action(self, mode):
        provider = self._model_provider(self.config["model"])
        if not self._get_api_key_for_provider(provider):
            self._prompt_for_api_key(provider)
            return
        self._run_fix_async(mode)

    def settings_clicked(self, _):
        self._open_settings()

    def open_config_folder(self, _):
        os.spawnlp(os.P_NOWAIT, "open", "open", str(CONFIG_DIR))

    def quit_app(self, _):
        rumps.quit_application()

    def _run_fix_async(self, mode="fix"):
        threading.Thread(target=self.fix_selection, args=(mode,), daemon=True).start()

    def fix_selection(self, mode="fix"):
        if not self._run_lock.acquire(blocking=False):
            self._notify("Already running", "Please wait for the current request.")
            return
        try:
            action = self._action_config(mode)
            provider = self._model_provider(self.config["model"])
            api_key = self._get_api_key_for_provider(provider)
            if not api_key:
                self._prompt_for_api_key(provider)
                return

            selected_text = self._copy_selection()
            if not selected_text.strip():
                self._notify("No text selected", "Highlight text and try again.")
                return

            display_text = f"{INLINE_SPINNER_PREFIX} {selected_text}"
            self._replace_selection_and_select_left(display_text, len(display_text))
            self._notify(action["in_progress_title"], "")
            fixed, error = self._rewrite_text(
                selected_text,
                api_key,
                provider,
                action["system_prompt"],
            )
            if not fixed:
                self._replace_selection(selected_text)
                self._handle_api_error(provider, error)
                return

            self._replace_selection(fixed)
            self._notify(action["success_title"], "")
        finally:
            self._run_lock.release()

    def _action_config(self, mode):
        if mode == "prompt":
            return {
                "system_prompt": self.config["prompt_system_prompt"],
                "in_progress_title": "Improving prompt…",
                "success_title": "Prompt rewritten and pasted",
            }
        return {
            "system_prompt": self.config["system_prompt"],
            "in_progress_title": "Fixing text…",
            "success_title": "Fixed and pasted",
        }

    def _rewrite_text(self, text, api_key, provider, system_prompt):
        if provider == "anthropic":
            return rewrite_text_anthropic(
                text,
                api_key,
                self.config["model"],
                system_prompt,
                self.config["temperature"],
                self.config["max_output_tokens"],
                timeout=30,
            )
        return rewrite_text(
            text,
            api_key,
            self.config["model"],
            system_prompt,
            self.config["temperature"],
            self.config["max_output_tokens"],
            timeout=30,
        )

    def _model_provider(self, model):
        if model.startswith("claude-"):
            return "anthropic"
        return "openai"

    def _get_api_key_for_provider(self, provider):
        if provider == "anthropic":
            return self.config.get("anthropic_api_key", "").strip()
        return self.config.get("openai_api_key", "").strip()

    def _run_on_main_thread(self, func, *args, **kwargs):
        if threading.current_thread() == threading.main_thread():
            func(*args, **kwargs)
            return
        AppHelper.callAfter(func, *args, **kwargs)

    def _prompt_for_api_key(self, provider):
        self._run_on_main_thread(self._prompt_for_api_key_on_main, provider)

    def _prompt_for_api_key_on_main(self, provider):
        alert = NSAlert.alloc().init()
        alert.setMessageText_("API key required")
        alert.setInformativeText_(f"Add your {provider.capitalize()} API key in Settings to continue.")
        alert.addButtonWithTitle_("Open Settings")
        alert.addButtonWithTitle_("Cancel")
        response = alert.runModal()
        if response == 1000:
            self._open_settings()

    def _prompt_for_api_key_issue(self, provider, detail):
        self._run_on_main_thread(self._prompt_for_api_key_issue_on_main, provider, detail)

    def _prompt_for_api_key_issue_on_main(self, provider, detail):
        alert = NSAlert.alloc().init()
        alert.setMessageText_("API key not accepted")
        detail_text = detail.strip() if detail else ""
        message = f"The {provider.capitalize()} API key was rejected. Update it in Settings."
        if detail_text:
            message = f"{message}\n\n{detail_text}"
        alert.setInformativeText_(message)
        alert.addButtonWithTitle_("Open Settings")
        alert.addButtonWithTitle_("Cancel")
        response = alert.runModal()
        if response == 1000:
            self._open_settings()

    def _handle_api_error(self, provider, error):
        detail = (error or "").strip()
        lower = detail.lower()
        auth_indicators = ("401", "403", "unauthorized", "invalid", "api key", "x-api-key")
        if any(token in lower for token in auth_indicators):
            self._prompt_for_api_key_issue(provider, detail)
            return
        title = "Request failed" if detail else "No response"
        message = detail or "Check your API key or network and retry."
        self._show_alert(title, message)

    def _copy_selection(self):
        pasteboard = NSPasteboard.generalPasteboard()
        change_count = pasteboard.changeCount()
        self._press_keycode(KEYCODE_MAP["c"], kCGEventFlagMaskCommand)
        for _ in range(COPY_POLL_ATTEMPTS):
            time.sleep(COPY_POLL_INTERVAL)
            if pasteboard.changeCount() != change_count:
                break
        return pasteboard.stringForType_(NSPasteboardTypeString) or ""

    def _set_clipboard(self, text):
        pasteboard = NSPasteboard.generalPasteboard()
        pasteboard.clearContents()
        pasteboard.setString_forType_(text, NSPasteboardTypeString)

    def _paste(self):
        self._press_keycode(KEYCODE_MAP["v"], kCGEventFlagMaskCommand)

    def _replace_selection(self, text):
        self._set_clipboard(text)
        self._paste()

    def _replace_selection_and_select_left(self, text, select_len):
        self._set_clipboard(text)
        self._paste()
        self._select_left(select_len)

    def _select_left(self, count):
        if count <= 0:
            return
        for _ in range(count):
            self._press_keycode(KEYCODE_MAP["left"], kCGEventFlagMaskShift)

    def _press_keycode(self, keycode, flags):
        event = CGEventCreateKeyboardEvent(None, keycode, True)
        if flags:
            CGEventSetFlags(event, flags)
        CGEventPost(kCGHIDEventTap, event)
        event = CGEventCreateKeyboardEvent(None, keycode, False)
        if flags:
            CGEventSetFlags(event, flags)
        CGEventPost(kCGHIDEventTap, event)

    def _open_settings(self):
        alert = NSAlert.alloc().init()
        alert.setMessageText_("TextFix Settings")
        alert.addButtonWithTitle_("Save")
        alert.addButtonWithTitle_("Cancel")

        view, fields, toggles = self._build_settings_view()
        alert.setAccessoryView_(view)
        response = alert.runModal()
        if response != 1000:
            return

        new_hotkey = fields["hotkey"].stringValue().strip()
        if new_hotkey and new_hotkey != self.config["hotkey"]:
            if not self._set_hotkey(new_hotkey):
                return
        new_prompt_hotkey = fields["prompt_hotkey"].stringValue().strip()
        if new_prompt_hotkey and new_prompt_hotkey != self.config["prompt_hotkey"]:
            if not self._set_prompt_hotkey(new_prompt_hotkey):
                return

        openai_key = fields["openai_api_key"].stringValue().strip()
        anthropic_key = fields["anthropic_api_key"].stringValue().strip()
        self.config["openai_api_key"] = openai_key
        self.config["anthropic_api_key"] = anthropic_key
        self.config["model"] = fields["model"].titleOfSelectedItem() or self.config["model"]
        self.config["temperature"] = self._parse_float(
            fields["temperature"].stringValue(), self.config["temperature"]
        )
        self.config["max_output_tokens"] = self._parse_int(
            fields["max_output_tokens"].stringValue(), self.config["max_output_tokens"]
        )
        prompt_text = fields["system_prompt"].string()
        if prompt_text is not None:
            self.config["system_prompt"] = prompt_text.strip() or self.config["system_prompt"]
        prompt_rewrite_text = fields["prompt_system_prompt"].string()
        if prompt_rewrite_text is not None:
            self.config["prompt_system_prompt"] = (
                prompt_rewrite_text.strip() or self.config["prompt_system_prompt"]
            )
        self.config["open_at_login"] = toggles["open_at_login"].state() == 1
        self.config["show_notifications"] = toggles["show_notifications"].state() == 1

        save_config(self.config)
        self._apply_login_item(self.config["open_at_login"])

    def _build_settings_view(self):
        width = 420
        row_height = 22
        row_gap = 10
        label_width = 160
        input_width = width - label_width - 24
        padding = 12

        rows = [
            ("Fix hotkey", "hotkey", self.config["hotkey"]),
            ("Prompt hotkey", "prompt_hotkey", self.config["prompt_hotkey"]),
            ("OpenAI API key", "openai_api_key", self.config.get("openai_api_key", "")),
            ("Anthropic API key", "anthropic_api_key", self.config.get("anthropic_api_key", "")),
            ("Model", "model", self.config["model"]),
            ("Temperature", "temperature", str(self.config["temperature"])),
            ("Max output tokens", "max_output_tokens", str(self.config["max_output_tokens"])),
            ("Fix prompt", "system_prompt", self.config["system_prompt"]),
            ("Prompt rewrite prompt", "prompt_system_prompt", self.config["prompt_system_prompt"]),
        ]

        prompt_height = 96
        multiline_keys = {"system_prompt", "prompt_system_prompt"}
        multiline_rows = [row for row in rows if row[1] in multiline_keys]
        standard_rows = [row for row in rows if row[1] not in multiline_keys]
        toggle_rows = [
            ("Open at login", "open_at_login", self.config.get("open_at_login", False)),
            ("Show notifications", "show_notifications", self.config.get("show_notifications", False)),
        ]
        total_height = (
            padding * 2
            + (row_height + row_gap) * (len(standard_rows) + len(toggle_rows))
            + (prompt_height + row_gap) * len(multiline_rows)
        )
        view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, width, total_height))

        fields = {}
        y = total_height - padding - row_height
        for label, key, value in rows:
            label_field = NSTextField.alloc().initWithFrame_(
                NSMakeRect(padding, y, label_width, row_height)
            )
            label_field.setStringValue_(label)
            label_field.setBezeled_(False)
            label_field.setDrawsBackground_(False)
            label_field.setEditable_(False)
            label_field.setSelectable_(False)

            if key in {"hotkey", "prompt_hotkey"}:
                input_field = HotkeyCaptureView.alloc().initWithFrame_(
                    NSMakeRect(padding + label_width, y, input_width, row_height)
                )
                input_field.setPlaceholderString_("Click and press keys")
            elif key in {"openai_api_key", "anthropic_api_key"}:
                input_field = PasteableSecureTextField.alloc().initWithFrame_(
                    NSMakeRect(padding + label_width, y, input_width, row_height)
                )
            elif key == "model":
                input_field = NSPopUpButton.alloc().initWithFrame_(
                    NSMakeRect(padding + label_width, y, input_width, row_height)
                )
                input_field.addItemsWithTitles_(MODEL_CHOICES)
                if value in MODEL_CHOICES:
                    input_field.selectItemWithTitle_(value)
                else:
                    input_field.addItemWithTitle_(value)
                    input_field.selectItemWithTitle_(value)
            elif key in multiline_keys:
                prompt_frame = NSMakeRect(
                    padding + label_width,
                    y - (prompt_height - row_height),
                    input_width,
                    prompt_height,
                )
                scroll = NSScrollView.alloc().initWithFrame_(prompt_frame)
                scroll.setHasVerticalScroller_(True)
                scroll.setBorderType_(1)
                text_view = NSTextView.alloc().initWithFrame_(NSMakeRect(0, 0, input_width, prompt_height))
                text_view.setString_(value)
                scroll.setDocumentView_(text_view)
                view.addSubview_(label_field)
                view.addSubview_(scroll)
                fields[key] = text_view
                y -= prompt_height + row_gap
                continue
            else:
                input_field = PasteableTextField.alloc().initWithFrame_(
                    NSMakeRect(padding + label_width, y, input_width, row_height)
                )
            input_field.setStringValue_(value)

            view.addSubview_(label_field)
            view.addSubview_(input_field)
            fields[key] = input_field

            y -= row_height + row_gap

        toggles = {}
        switch_width = 44
        switch_height = 22
        for label, key, value in toggle_rows:
            label_field = NSTextField.alloc().initWithFrame_(
                NSMakeRect(padding, y, label_width, row_height)
            )
            label_field.setStringValue_(label)
            label_field.setBezeled_(False)
            label_field.setDrawsBackground_(False)
            label_field.setEditable_(False)
            label_field.setSelectable_(False)

            switch_x = width - padding - switch_width
            switch_y = y + (row_height - switch_height) / 2
            toggle = NSSwitch.alloc().initWithFrame_(
                NSMakeRect(switch_x, switch_y, switch_width, switch_height)
            )
            toggle.setState_(1 if value else 0)

            view.addSubview_(label_field)
            view.addSubview_(toggle)
            toggles[key] = toggle

            y -= row_height + row_gap

        return view, fields, toggles

    def _set_hotkey(self, hotkey):
        spec = parse_hotkey(hotkey)
        if not spec:
            self._show_alert(
                "Invalid hotkey",
                "Use format like <cmd>+<shift>+g",
            )
            return False
        self.hotkey_spec = spec
        self.config["hotkey"] = hotkey
        return True

    def _set_prompt_hotkey(self, hotkey):
        spec = parse_hotkey(hotkey)
        if not spec:
            self._show_alert(
                "Invalid prompt hotkey",
                "Use format like <cmd>+<option>+g",
            )
            return False
        self.prompt_hotkey_spec = spec
        self.config["prompt_hotkey"] = hotkey
        return True

    def _parse_float(self, value, default):
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    def _parse_int(self, value, default):
        try:
            return int(value)
        except (TypeError, ValueError):
            return default

    def _login_item_plist_path(self):
        return Path.home() / "Library/LaunchAgents/com.textfix.app.plist"

    def _program_arguments_for_login(self):
        exec_path = Path(sys.argv[0]).resolve()
        bundle_path = None
        for parent in exec_path.parents:
            if parent.suffix == ".app":
                bundle_path = parent
                break
        if bundle_path:
            return ["/usr/bin/open", "-a", str(bundle_path)]
        return [sys.executable, str(Path(__file__).resolve())]

    def _write_login_item_plist(self, plist_path):
        plist = {
            "Label": "com.textfix.app",
            "ProgramArguments": self._program_arguments_for_login(),
            "RunAtLoad": True,
            "KeepAlive": False,
        }
        plist_path.parent.mkdir(parents=True, exist_ok=True)
        with plist_path.open("wb") as f:
            plistlib.dump(plist, f)

    def _launchctl(self, *args):
        try:
            result = subprocess.run(
                ["/bin/launchctl", *args],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError:
            return False
        return result.returncode == 0

    def _apply_login_item(self, enabled):
        plist_path = self._login_item_plist_path()
        try:
            if enabled:
                self._write_login_item_plist(plist_path)
                uid = os.getuid()
                if not self._launchctl("bootstrap", f"gui/{uid}", str(plist_path)):
                    self._launchctl("load", "-w", str(plist_path))
                return

            uid = os.getuid()
            if not self._launchctl("bootout", f"gui/{uid}", str(plist_path)):
                self._launchctl("unload", "-w", str(plist_path))
            if plist_path.exists():
                plist_path.unlink()
        except OSError as exc:
            print(f"Unable to update login item: {exc}", file=sys.stderr)

    def _setup_hotkey_tap(self):
        def callback(_proxy, event_type, event, _refcon):
            if event_type != kCGEventKeyDown:
                return event
            keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)
            flags = CGEventGetFlags(event)
            if hotkey_matches_event(self.prompt_hotkey_spec, keycode, flags):
                self.on_prompt_hotkey()
                return event
            if hotkey_matches_event(self.hotkey_spec, keycode, flags):
                self.on_hotkey()
            return event

        self._hotkey_tap_callback = callback
        self._hotkey_tap = CGEventTapCreate(
            kCGHIDEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionListenOnly,
            1 << kCGEventKeyDown,
            self._hotkey_tap_callback,
            None,
        )
        if not self._hotkey_tap:
            self._notify(
                "Hotkey disabled",
                "Enable Input Monitoring for TextFix, then relaunch.",
            )
            return

        self._hotkey_source = CFMachPortCreateRunLoopSource(None, self._hotkey_tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), self._hotkey_source, kCFRunLoopCommonModes)
        CGEventTapEnable(self._hotkey_tap, True)

    def _show_alert(self, title, message):
        self._run_on_main_thread(self._show_alert_on_main, title, message)

    def _show_alert_on_main(self, title, message):
        alert = NSAlert.alloc().init()
        alert.setMessageText_(title)
        alert.setInformativeText_(message)
        alert.addButtonWithTitle_("OK")
        alert.runModal()

    def _ensure_accessibility(self):
        if not AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: True}):
            self._notify(
                "Accessibility permission required",
                "Enable TextFix in System Settings > Privacy & Security > Accessibility, then relaunch.",
            )

    def _notify(self, title, message):
        if not self.config.get("show_notifications", False):
            return
        rumps.notification(APP_NAME, title, message)


if __name__ == "__main__":
    TextFixApp().run()
