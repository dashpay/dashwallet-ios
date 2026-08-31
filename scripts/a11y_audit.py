#!/usr/bin/env python3
"""
Accessibility (VoiceOver / Dynamic Type) static audit for dashwallet-ios.

Finds interactive controls that a screen reader cannot announce, and text that
ignores the user's Dynamic Type setting. Written for ticket 32072.

No third-party dependencies — stdlib only, Python 3.8+.

Usage
-----
  scripts/a11y_audit.py                       # human-readable report
  scripts/a11y_audit.py --summary             # counts only
  scripts/a11y_audit.py --rule A11Y001        # one rule (repeatable)
  scripts/a11y_audit.py --json report.json    # machine-readable
  scripts/a11y_audit.py --github              # GitHub Actions annotations
  scripts/a11y_audit.py --write-baseline      # record today's debt as accepted
  scripts/a11y_audit.py --check               # fail only on NEW findings

`--check` is the CI mode: it compares against scripts/a11y_baseline.json and
exits non-zero only when a finding appears that is not in the baseline. Existing
debt never fails the build, so the ratchet can be adopted without fixing
everything first.

Suppressing a finding
---------------------
Put a comment on the offending line or the line above it:

    // a11y-ignore: A11Y004 decorative chevron, row itself is labeled

The rule id is required; the reason is required and must be non-empty.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import Counter, defaultdict
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

SCAN_ROOTS = ["DashWallet", "TodayExtension", "WatchApp", "WatchApp Extension"]

EXCLUDED_DIR_NAMES = {
    "Pods", "build", "DerivedData", ".build", ".git", "Carthage",
    "fastlane", "vendor", "node_modules",
}

SWIFT_EXT = ".swift"
OBJC_EXTS = (".m", ".mm")
IB_EXTS = (".xib", ".storyboard")

BASELINE_PATH = os.path.join("scripts", "a11y_baseline.json")

# Apple's own SwiftUI Font text styles. Redeclaring any of these in an
# app-module `extension Font` silently shadows the scaling system font.
SYSTEM_FONT_STYLES = {
    "largeTitle", "title", "title2", "title3", "headline", "subheadline",
    "body", "callout", "footnote", "caption", "caption2",
}

# Things that make a SwiftUI view announce itself without an explicit label.
SPEAKS_FOR_ITSELF = (
    "Text(", "Label(", "TextField(", "SecureField(", "Link(",
    "LocalizedStringKey", "NSLocalizedString", "verbatim:",
)

ACCESSIBILITY_ESCAPES = (
    ".accessibilityLabel", ".accessibilityElement", ".accessibilityHidden",
    ".accessibilityRepresentation", ".accessibilityValue", ".labelsHidden",
    ".accessibility(label:", "accessibilityLabel =",
)

SEVERITY_ORDER = {"P0": 0, "P1": 1, "P2": 2}

CONFIG_PATH = os.path.join("scripts", "a11y_config.json")


class Config:
    """Project-specific tuning, so a design system does not fight the rules.

    Loaded from scripts/a11y_config.json when present; every field is optional.
    """

    def __init__(self, data: Optional[Dict[str, object]] = None) -> None:
        data = data or {}
        # Rules that never run at all.
        self.disabled_rules: Set[str] = set(data.get("disabled_rules") or [])
        # Rules that report but never fail --check, whatever their severity.
        self.advisory_rules: Set[str] = set(data.get("advisory_rules") or [])
        # Path prefixes skipped entirely (debug screens, generated code).
        self.exclude_paths: List[str] = list(data.get("exclude_paths") or [])
        # Wrapper components that guarantee a label themselves. A view built
        # from one of these is treated as already announced.
        self.labeled_wrappers: List[str] = list(data.get("labeled_wrappers") or [])
        # Extra tokens that mean "this view speaks for itself" — e.g. a custom
        # component whose API requires a title.
        self.speaks_for_itself: List[str] = list(data.get("speaks_for_itself") or [])
        # Font token names the project deliberately keeps despite shadowing
        # an Apple text style.
        self.allowed_font_shadows: Set[str] = set(
            data.get("allowed_font_shadows") or [])

    def speaks_tokens(self) -> Tuple[str, ...]:
        return SPEAKS_FOR_ITSELF + tuple(self.speaks_for_itself) \
            + tuple(self.labeled_wrappers)

    def escape_tokens(self) -> Tuple[str, ...]:
        return ACCESSIBILITY_ESCAPES + tuple(self.labeled_wrappers)

    def excluded(self, rel_path: str) -> bool:
        normalized = rel_path.replace(os.sep, "/")
        return any(normalized.startswith(prefix.rstrip("/") )
                   for prefix in self.exclude_paths)


CONFIG = Config()


def load_config(repo_root: str, path: str) -> Config:
    abs_path = os.path.join(repo_root, path)
    if not os.path.exists(abs_path):
        return Config()
    with open(abs_path, "r", encoding="utf-8") as handle:
        return Config(json.load(handle))


def has_real_title(args: str) -> bool:
    """True when a `title:` argument is present and is not nil.

    Written as an explicit value match rather than a negative lookahead: with
    `title\\s*:\\s*(?!nil)` the `\\s*` backtracks to zero width and the lookahead
    then passes on the space, so `title: nil` reads as a real title.
    """
    match = re.search(r"title\s*:\s*(\S+)", args)
    if not match:
        return False
    return match.group(1).rstrip(",)") != "nil"


class Rule:
    def __init__(self, rid: str, severity: str, title: str, fix: str) -> None:
        self.id = rid
        self.severity = severity
        self.title = title
        self.fix = fix


RULES: Dict[str, Rule] = {
    r.id: r
    for r in [
        Rule("A11Y001", "P0", "Tab bar item with no accessibility label",
             "Set item.accessibilityLabel to a localized name."),
        Rule("A11Y002", "P1", "Icon-only UIBarButtonItem with no label",
             "Set .accessibilityLabel on the bar button item."),
        Rule("A11Y003", "P1", "Icon-only UIButton with no label",
             "Set .accessibilityLabel, or give the button a title."),
        Rule("A11Y004", "P1", "Icon-only SwiftUI Button with no label",
             "Add .accessibilityLabel(Text(NSLocalizedString(...)))."),
        Rule("A11Y005", "P1", "Toggle with an empty label",
             "Give the Toggle a label, or set .accessibilityLabel on it."),
        Rule("A11Y006", "P1", "Custom back button replaces the labeled system one",
             "Set .accessibilityLabel on the custom back button."),
        Rule("A11Y007", "P2", "Fixed font size ignores Dynamic Type",
             "Use .system(size:..., relativeTo: .body) or a text style."),
        Rule("A11Y008", "P0", "extension Font shadows an Apple text style",
             "Rename the token; a shadowed style silently stops scaling."),
        Rule("A11Y009", "P1", "accessibilityLabel is not localized",
             "Wrap the string in NSLocalizedString."),
        Rule("A11Y010", "P1", "accessibilityLabel key missing from en.lproj",
             "Add the key to DashWallet/en.lproj/Localizable.strings."),
        Rule("A11Y011", "P1", "Image-only control in a xib/storyboard with no label",
             "Add an <accessibility> node with a label in Interface Builder."),
        Rule("A11Y012", "P1", "Tap gesture on a view with no accessibility",
             "Use a Button, or add .accessibilityElement + label + .isButton trait."),
    ]
}


class Finding:
    __slots__ = ("rule_id", "path", "line", "snippet", "detail")

    def __init__(self, rule_id: str, path: str, line: int, snippet: str,
                 detail: str = "") -> None:
        self.rule_id = rule_id
        self.path = path
        self.line = line
        self.snippet = snippet.strip()[:160]
        self.detail = detail

    @property
    def severity(self) -> str:
        return RULES[self.rule_id].severity

    def fingerprint(self) -> str:
        """Stable across line moves and reindentation, unlike a line number."""
        normalized = re.sub(r"\s+", "", self.snippet)
        payload = "{}|{}|{}".format(self.rule_id, self.path, normalized)
        return hashlib.sha1(payload.encode("utf-8")).hexdigest()[:16]

    def key(self) -> Tuple[str, str, str]:
        return (self.rule_id, self.path, self.fingerprint())

    def to_dict(self) -> Dict[str, object]:
        return {
            "rule": self.rule_id,
            "severity": self.severity,
            "title": RULES[self.rule_id].title,
            "path": self.path,
            "line": self.line,
            "snippet": self.snippet,
            "detail": self.detail,
            "fingerprint": self.fingerprint(),
        }


# --------------------------------------------------------------------------
# Source helpers
# --------------------------------------------------------------------------

def iter_files(repo_root: str, roots: Sequence[str],
               extensions: Tuple[str, ...]) -> Iterable[str]:
    for root in roots:
        abs_root = os.path.join(repo_root, root)
        if not os.path.isdir(abs_root):
            continue
        for dirpath, dirnames, filenames in os.walk(abs_root):
            dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIR_NAMES]
            for name in sorted(filenames):
                if name.endswith(extensions):
                    abs_path = os.path.join(dirpath, name)
                    yield os.path.relpath(abs_path, repo_root)


def read(repo_root: str, rel_path: str) -> str:
    abs_path = os.path.join(repo_root, rel_path)
    if not os.path.exists(abs_path):
        return ""
    for encoding in ("utf-8", "utf-16", "latin-1"):
        try:
            with open(abs_path, "r", encoding=encoding) as handle:
                return handle.read()
        except (UnicodeDecodeError, UnicodeError):
            continue
    return ""


def strip_comments(text: str) -> str:
    """Blank out comments and string bodies, preserving offsets and newlines.

    Keeping length identical means every offset computed on the stripped text
    still points at the right place in the original.
    """
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif ch == "/" and nxt == "*":
            depth = 1
            out[i] = out[i + 1] = " "
            i += 2
            while i < n and depth:
                if text[i] == "/" and i + 1 < n and text[i + 1] == "*":
                    depth += 1
                    out[i] = out[i + 1] = " "
                    i += 2
                    continue
                if text[i] == "*" and i + 1 < n and text[i + 1] == "/":
                    depth -= 1
                    out[i] = out[i + 1] = " "
                    i += 2
                    continue
                if text[i] != "\n":
                    out[i] = " "
                i += 1
        elif ch == '"':
            # Leave the quotes, blank the body: rules that look for string
            # literals still see "" and can tell an empty label from a real one.
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\" and i + 1 < n:
                    out[i] = out[i + 1] = " "
                    i += 2
                    continue
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            i += 1
        else:
            i += 1
    return "".join(out)


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def line_text(text: str, line_no: int) -> str:
    lines = text.splitlines()
    if 1 <= line_no <= len(lines):
        return lines[line_no - 1]
    return ""


def balanced_block(text: str, open_pos: int) -> Optional[int]:
    """Given the offset of a '{', return the offset just past its '}'."""
    if open_pos >= len(text) or text[open_pos] != "{":
        return None
    depth = 0
    for i in range(open_pos, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    return None


def balanced_parens(text: str, open_pos: int) -> Optional[int]:
    if open_pos >= len(text) or text[open_pos] != "(":
        return None
    depth = 0
    for i in range(open_pos, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
    return None


def modifier_tail(text: str, end_pos: int, max_chars: int = 700) -> str:
    """The chained modifiers that follow a view expression."""
    return text[end_pos:end_pos + max_chars]


def suppressed(original: str, line_no: int, rule_id: str) -> bool:
    """`// a11y-ignore: RULEID reason` on this line or the one above."""
    for candidate in (line_no, line_no - 1):
        raw = line_text(original, candidate)
        match = re.search(r"a11y-ignore:\s*([A-Z0-9]+)\s+(\S.*)$", raw)
        if match and match.group(1) == rule_id and match.group(2).strip():
            return True
    return False


def add(findings: List[Finding], original: str, rule_id: str, path: str,
        offset_or_line, snippet: str, detail: str = "",
        text_for_offsets: Optional[str] = None) -> None:
    if isinstance(offset_or_line, int) and text_for_offsets is not None:
        line_no = line_of(text_for_offsets, offset_or_line)
    else:
        line_no = int(offset_or_line)
    if suppressed(original, line_no, rule_id):
        return
    findings.append(Finding(rule_id, path, line_no, snippet, detail))


# --------------------------------------------------------------------------
# Rules — UIKit
# --------------------------------------------------------------------------

def _receiver_of_assignment(line: str) -> Optional[str]:
    """`var item = UITabBarItem(...)` -> 'item'."""
    match = re.search(r"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
    if match:
        return match.group(1)
    match = re.search(r"^\s*(?:self\.)?([A-Za-z_][A-Za-z0-9_]*)\s*=", line)
    if match:
        return match.group(1)
    return None


def _labeled_nearby(code: str, start: int, receiver: Optional[str],
                    window: int = 1200) -> bool:
    region = code[start:start + window]
    if receiver:
        if re.search(re.escape(receiver) + r"\s*\.\s*accessibilityLabel\s*=", region):
            return True
        # `item.accessibilityLabel = ...` may also be written via a helper
        if re.search(re.escape(receiver) + r"\s*\.\s*isAccessibilityElement", region):
            return True
    return False


def rule_tabbar(code: str, original: str, path: str,
                findings: List[Finding]) -> None:
    for match in re.finditer(r"UITabBarItem\s*\(", code):
        open_paren = match.end() - 1
        close = balanced_parens(code, open_paren)
        if close is None:
            continue
        args = code[open_paren:close]
        # A tab with a real title announces itself.
        if has_real_title(args):
            continue
        line_no = line_of(code, match.start())
        receiver = _receiver_of_assignment(line_text(original, line_no))
        if _labeled_nearby(code, close, receiver):
            continue
        add(findings, original, "A11Y001", path, line_no,
            line_text(original, line_no),
            "title: nil and no accessibilityLabel — VoiceOver falls back to the "
            "image asset name")


def rule_barbuttonitem(code: str, original: str, path: str,
                       findings: List[Finding]) -> None:
    for match in re.finditer(r"UIBarButtonItem\s*\(", code):
        open_paren = match.end() - 1
        close = balanced_parens(code, open_paren)
        if close is None:
            continue
        args = code[open_paren:close]
        if "image" not in args and "customView" not in args:
            continue
        if has_real_title(args):
            continue
        if re.search(r"barButtonSystemItem\s*:", args):
            continue  # system items are labeled by UIKit
        line_no = line_of(code, match.start())
        receiver = _receiver_of_assignment(line_text(original, line_no))
        if _labeled_nearby(code, close, receiver):
            continue
        add(findings, original, "A11Y002", path, line_no,
            line_text(original, line_no),
            "image-only bar button with no accessibilityLabel")


def rule_uibutton(code: str, original: str, path: str,
                  findings: List[Finding]) -> None:
    """UIButton that only ever gets an image, never a title or a label."""
    for match in re.finditer(r"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
                             r"UIButton\s*\(", code):
        name = match.group(1)
        region = code[match.end():match.end() + 1500]
        sets_image = re.search(re.escape(name) + r"\s*\.\s*setImage\s*\(", region)
        if not sets_image:
            continue
        sets_title = re.search(
            re.escape(name) + r"\s*\.\s*(setTitle|setAttributedTitle)\s*\(", region)
        if sets_title:
            continue
        if re.search(re.escape(name) + r"\s*\.\s*accessibilityLabel\s*=", region):
            continue
        line_no = line_of(code, match.start())
        is_back = "back" in name.lower()
        rule_id = "A11Y006" if is_back else "A11Y003"
        detail = ("custom back button replaces UIKit's automatically labeled "
                  "system back button" if is_back
                  else "setImage without setTitle and without accessibilityLabel")
        add(findings, original, rule_id, path, line_no,
            line_text(original, line_no), detail)


# --------------------------------------------------------------------------
# Rules — SwiftUI
# --------------------------------------------------------------------------

def _block_speaks(block: str) -> bool:
    return any(token in block for token in CONFIG.speaks_tokens())


def _block_has_visual(block: str) -> bool:
    return bool(re.search(r"\bImage\s*\(|\bIcon\s*\(|systemName\s*:|"
                          r"\bCircle\s*\(|\bRoundedRectangle\s*\(", block))


def _tail_escapes(tail: str) -> bool:
    return any(token in tail for token in CONFIG.escape_tokens())


def rule_swiftui_button(code: str, original: str, path: str,
                        findings: List[Finding]) -> None:
    for match in re.finditer(r"\bButton\s*(\(|\{)", code):
        opener = match.end() - 1
        if code[opener] == "(":
            close_paren = balanced_parens(code, opener)
            if close_paren is None:
                continue
            args = code[opener:close_paren]
            # Button("Title", action:) announces its title.
            if _block_speaks(args):
                continue
            brace = code.find("{", close_paren)
            if brace == -1 or brace - close_paren > 4:
                # No trailing closure: Button(action:) with no label body.
                continue
        else:
            brace = opener
        block_end = balanced_block(code, brace)
        if block_end is None:
            continue
        block = code[brace:block_end]
        if _block_speaks(block):
            continue
        if not _block_has_visual(block):
            continue
        tail = modifier_tail(code, block_end)
        if _tail_escapes(tail):
            continue
        if _tail_escapes(block):
            continue
        line_no = line_of(code, match.start())
        add(findings, original, "A11Y004", path, line_no,
            line_text(original, line_no),
            "button label is an image/shape with no text and no "
            ".accessibilityLabel")


def rule_toggle(code: str, original: str, path: str,
                findings: List[Finding]) -> None:
    for match in re.finditer(r"\bToggle\s*\(", code):
        open_paren = match.end() - 1
        close = balanced_parens(code, open_paren)
        if close is None:
            continue
        args = code[open_paren:close]
        if _block_speaks(args):
            continue
        brace = code.find("{", close)
        empty_label = False
        end_of_toggle = close
        if brace != -1 and brace - close <= 3:
            block_end = balanced_block(code, brace)
            if block_end is not None:
                block = code[brace + 1:block_end - 1]
                end_of_toggle = block_end
                if not block.strip():
                    empty_label = True
                elif not _block_speaks(block):
                    empty_label = True
        else:
            # Toggle(isOn:) with no label argument at all
            empty_label = '""' in args or "isOn" in args and not _block_speaks(args)
        if not empty_label:
            continue
        tail = modifier_tail(code, end_of_toggle)
        if _tail_escapes(tail):
            continue
        line_no = line_of(code, match.start())
        add(findings, original, "A11Y005", path, line_no,
            line_text(original, line_no),
            "switch is announced with no indication of what it controls")


def rule_tap_gesture(code: str, original: str, path: str,
                     findings: List[Finding]) -> None:
    """`.onTapGesture` with no accessibility treatment anywhere near it."""
    for match in re.finditer(r"\.onTapGesture\s*(\{|\()", code):
        # Look both ways: the modifier chain around this view.
        before = code[max(0, match.start() - 900):match.start()]
        opener = match.end() - 1
        block_end = (balanced_block(code, opener) if code[opener] == "{"
                     else balanced_parens(code, opener))
        after_start = block_end if block_end else match.end()
        after = code[after_start:after_start + 600]
        if _tail_escapes(before) or _tail_escapes(after):
            continue
        # A tap gesture attached to something that already reads as text is a
        # smaller problem than a bare icon, but still unreachable by trait.
        line_no = line_of(code, match.start())
        add(findings, original, "A11Y012", path, line_no,
            line_text(original, line_no),
            "tap target is invisible to VoiceOver — no button trait, no label")


# --------------------------------------------------------------------------
# Rules — Dynamic Type
# --------------------------------------------------------------------------

def rule_font_shadowing(code: str, original: str, path: str,
                        findings: List[Finding]) -> None:
    for match in re.finditer(r"extension\s+Font\b", code):
        brace = code.find("{", match.end())
        if brace == -1:
            continue
        block_end = balanced_block(code, brace)
        if block_end is None:
            continue
        block = code[brace:block_end]
        for decl in re.finditer(
                r"static\s+(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:", block):
            name = decl.group(1)
            if name not in SYSTEM_FONT_STYLES:
                continue
            if name in CONFIG.allowed_font_shadows:
                continue
            line_no = line_of(code, brace + decl.start())
            add(findings, original, "A11Y008", path, line_no,
                line_text(original, line_no),
                "shadows SwiftUI's Font.{} — every .font(.{}) call in this "
                "module silently stops scaling".format(name, name))


def rule_fixed_font_size(code: str, original: str, path: str,
                         findings: List[Finding]) -> None:
    for match in re.finditer(r"\.system\s*\(\s*size\s*:", code):
        close = balanced_parens(code, code.rindex("(", 0, match.end()))
        args = code[match.start():close] if close else code[match.start():match.end() + 120]
        if "relativeTo" in args:
            continue
        line_no = line_of(code, match.start())
        add(findings, original, "A11Y007", path, line_no,
            line_text(original, line_no),
            "fixed point size with no relativeTo: — ignores the user's text size")


# --------------------------------------------------------------------------
# Rules — localization of the labels that do exist
# --------------------------------------------------------------------------

def load_en_strings(repo_root: str) -> Set[str]:
    keys: Set[str] = set()
    for rel in ("DashWallet/en.lproj/Localizable.strings",
                "DashWallet/Base.lproj/Localizable.strings"):
        content = read(repo_root, rel)
        for match in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', content,
                                 re.MULTILINE):
            keys.add(match.group(1))
    return keys


def rule_label_localization(original: str, path: str, en_keys: Set[str],
                            findings: List[Finding]) -> None:
    """Runs on the ORIGINAL text — string bodies matter here."""
    for match in re.finditer(r"\.accessibilityLabel\s*\(", original):
        open_paren = match.end() - 1
        close = balanced_parens(original, open_paren)
        if close is None:
            continue
        args = original[open_paren:close]
        line_no = line_of(original, match.start())
        if "NSLocalizedString" in args or "LocalizedStringKey" in args:
            key = re.search(r'NSLocalizedString\s*\(\s*"((?:[^"\\]|\\.)*)"', args)
            if key and en_keys and key.group(1) not in en_keys:
                add(findings, original, "A11Y010", path, line_no,
                    line_text(original, line_no),
                    'key "{}" is not in en.lproj/Localizable.strings — ships '
                    "untranslated".format(key.group(1)))
            continue
        if "verbatim:" in args:
            continue  # deliberate, e.g. a currency ticker
        if re.search(r'"\s*(?:[^"\\]|\\.)+\s*"', args):
            add(findings, original, "A11Y009", path, line_no,
                line_text(original, line_no),
                "bare string literal — this label ships in English only")


# --------------------------------------------------------------------------
# Rules — Interface Builder
# --------------------------------------------------------------------------

IB_INTERACTIVE = ("<button", "<barButtonItem", "<segmentedControl", "<slider",
                  "<switch", "<textField", "<searchBar", "<tabBarItem")


def rule_interface_builder(content: str, path: str,
                           findings: List[Finding]) -> None:
    lines = content.splitlines()
    for index, raw in enumerate(lines):
        stripped = raw.strip()
        if not any(stripped.startswith(tag) for tag in IB_INTERACTIVE):
            continue
        # Self-closing elements carry no children, so no accessibility node.
        element_lines = [raw]
        if not stripped.endswith("/>"):
            depth_probe = index + 1
            while depth_probe < len(lines) and depth_probe < index + 40:
                element_lines.append(lines[depth_probe])
                if lines[depth_probe].strip().startswith("</"):
                    break
                depth_probe += 1
        blob = "\n".join(element_lines)
        if "<accessibility" in blob and "label=" in blob:
            continue
        has_title = re.search(r'\stitle="[^"]+"|<state[^>]+title="[^"]+"', blob)
        if has_title:
            continue
        has_image = re.search(r'image="[^"]+"', blob)
        if not has_image:
            continue
        if suppressed(content, index + 1, "A11Y011"):
            continue
        findings.append(Finding("A11Y011", path, index + 1, stripped,
                                "image-only control with no accessibility label "
                                "in Interface Builder"))


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

def analyze(repo_root: str, roots: Sequence[str],
            enabled: Optional[Set[str]]) -> List[Finding]:
    findings: List[Finding] = []
    en_keys = load_en_strings(repo_root)

    def on(rule_id: str) -> bool:
        if rule_id in CONFIG.disabled_rules:
            return False
        return enabled is None or rule_id in enabled

    for rel in iter_files(repo_root, roots, (SWIFT_EXT,) + OBJC_EXTS):
        if CONFIG.excluded(rel):
            continue
        original = read(repo_root, rel)
        if not original:
            continue
        code = strip_comments(original)
        if on("A11Y001"):
            rule_tabbar(code, original, rel, findings)
        if on("A11Y002"):
            rule_barbuttonitem(code, original, rel, findings)
        if on("A11Y003") or on("A11Y006"):
            rule_uibutton(code, original, rel, findings)
        if rel.endswith(SWIFT_EXT):
            if on("A11Y004"):
                rule_swiftui_button(code, original, rel, findings)
            if on("A11Y005"):
                rule_toggle(code, original, rel, findings)
            if on("A11Y012"):
                rule_tap_gesture(code, original, rel, findings)
            if on("A11Y008"):
                rule_font_shadowing(code, original, rel, findings)
            if on("A11Y007"):
                rule_fixed_font_size(code, original, rel, findings)
        if on("A11Y009") or on("A11Y010"):
            rule_label_localization(original, rel, en_keys, findings)

    if on("A11Y011"):
        for rel in iter_files(repo_root, roots, IB_EXTS):
            if CONFIG.excluded(rel):
                continue
            content = read(repo_root, rel)
            if content:
                rule_interface_builder(content, rel, findings)

    findings = [f for f in findings if f.rule_id not in CONFIG.disabled_rules]
    if enabled is not None:
        findings = [f for f in findings if f.rule_id in enabled]

    findings.sort(key=lambda f: (SEVERITY_ORDER[f.severity], f.rule_id,
                                 f.path, f.line))
    return findings


def load_baseline(repo_root: str, path: str) -> Optional[Set[Tuple[str, str, str]]]:
    abs_path = os.path.join(repo_root, path)
    if not os.path.exists(abs_path):
        return None
    with open(abs_path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    return {(item["rule"], item["path"], item["fingerprint"])
            for item in data.get("findings", [])}


def write_baseline(repo_root: str, path: str,
                   findings: List[Finding]) -> None:
    abs_path = os.path.join(repo_root, path)
    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    payload = {
        "_comment": [
            "Accepted accessibility debt, recorded by scripts/a11y_audit.py.",
            "CI fails only on findings that are NOT in this list, so the debt",
            "can shrink over time without blocking unrelated work.",
            "Regenerate with: scripts/a11y_audit.py --write-baseline",
        ],
        "counts": dict(Counter(f.rule_id for f in findings)),
        "total": len(findings),
        "findings": [
            {"rule": f.rule_id, "path": f.path, "fingerprint": f.fingerprint(),
             "line_when_recorded": f.line, "snippet": f.snippet}
            for f in findings
        ],
    }
    with open(abs_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def print_report(findings: List[Finding], summary_only: bool) -> None:
    by_rule = defaultdict(list)
    for f in findings:
        by_rule[f.rule_id].append(f)

    print("Accessibility audit — dashwallet-ios")
    print("=" * 72)
    if not findings:
        print("No findings.")
        return

    by_sev = Counter(f.severity for f in findings)
    print("{} findings   P0={}  P1={}  P2={}".format(
        len(findings), by_sev["P0"], by_sev["P1"], by_sev["P2"]))
    print()
    print("{:<9} {:<4} {:>6}  {}".format("RULE", "SEV", "COUNT", "TITLE"))
    print("-" * 72)
    for rule_id in sorted(by_rule, key=lambda r: (SEVERITY_ORDER[RULES[r].severity], r)):
        rule = RULES[rule_id]
        print("{:<9} {:<4} {:>6}  {}".format(
            rule_id, rule.severity, len(by_rule[rule_id]), rule.title))

    if summary_only:
        return

    for rule_id in sorted(by_rule, key=lambda r: (SEVERITY_ORDER[RULES[r].severity], r)):
        rule = RULES[rule_id]
        items = by_rule[rule_id]
        print()
        print("-" * 72)
        print("{} [{}] {}  ({} findings)".format(
            rule_id, rule.severity, rule.title, len(items)))
        print("Fix: {}".format(rule.fix))
        print("-" * 72)
        shown = items[:40]
        for f in shown:
            print("  {}:{}".format(f.path, f.line))
            if f.snippet:
                print("      {}".format(f.snippet))
            if f.detail:
                print("      -> {}".format(f.detail))
        if len(items) > len(shown):
            print("  ... and {} more".format(len(items) - len(shown)))


def print_github(findings: List[Finding]) -> None:
    for f in findings:
        level = "error" if f.severity == "P0" else "warning"
        message = "{}: {}".format(RULES[f.rule_id].title, f.detail or f.snippet)
        message = message.replace("\n", " ").replace("::", ":")
        print("::{} file={},line={},title={}::{}".format(
            level, f.path, f.line, f.rule_id, message))


# --------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------

def _analyze_source(source: str, path: str = "Fixture.swift",
                    en_keys: Optional[Set[str]] = None) -> List[Finding]:
    findings: List[Finding] = []
    code = strip_comments(source)
    rule_tabbar(code, source, path, findings)
    rule_barbuttonitem(code, source, path, findings)
    rule_uibutton(code, source, path, findings)
    rule_swiftui_button(code, source, path, findings)
    rule_toggle(code, source, path, findings)
    rule_tap_gesture(code, source, path, findings)
    rule_font_shadowing(code, source, path, findings)
    rule_fixed_font_size(code, source, path, findings)
    rule_label_localization(source, path, en_keys or set(), findings)
    return findings


# (rule id, should the rule fire, source)
FIXTURES: List[Tuple[str, bool, str]] = [
    # A11Y001 — tab bar
    ("A11Y001", True,
     'let item = UITabBarItem(title: nil, image: icon, selectedImage: sel)\n'),
    ("A11Y001", False,
     'let item = UITabBarItem(title: nil, image: icon, selectedImage: sel)\n'
     'item.accessibilityLabel = NSLocalizedString("Home", comment: "")\n'),
    ("A11Y001", False,
     'let item = UITabBarItem(title: "Home", image: icon, selectedImage: sel)\n'),

    # A11Y002 — bar button item
    ("A11Y002", True,
     'let b = UIBarButtonItem(image: img, style: .plain, target: self, action: nil)\n'),
    ("A11Y002", False,
     'let b = UIBarButtonItem(image: img, style: .plain, target: self, action: nil)\n'
     'b.accessibilityLabel = NSLocalizedString("Notifications", comment: "")\n'),
    ("A11Y002", False,
     'let b = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: nil)\n'),

    # A11Y003 / A11Y006 — UIButton
    ("A11Y003", True,
     'let infoButton = UIButton(type: .custom)\n'
     'infoButton.setImage(UIImage(named: "info"), for: .normal)\n'),
    ("A11Y003", False,
     'let infoButton = UIButton(type: .custom)\n'
     'infoButton.setImage(UIImage(named: "info"), for: .normal)\n'
     'infoButton.setTitle("Info", for: .normal)\n'),
    ("A11Y006", True,
     'let backButton = UIButton(type: .custom)\n'
     'backButton.setImage(UIImage(systemName: "arrow.backward"), for: .normal)\n'),

    # A11Y004 — SwiftUI button
    ("A11Y004", True,
     'Button(action: onClose) {\n    Image(systemName: "xmark")\n}\n'),
    ("A11Y004", False,
     'Button(action: onClose) {\n    Image(systemName: "xmark")\n}\n'
     '.accessibilityLabel(Text("Close"))\n'),
    ("A11Y004", False,
     'Button(action: onClose) {\n    Text("Close")\n}\n'),
    ("A11Y004", False,
     'Button("Close", action: onClose)\n'),
    ("A11Y004", False,
     'Button(action: onClose) {\n    Image(systemName: "xmark")\n'
     '        .accessibilityHidden(true)\n}\n'
     '.accessibilityLabel(Text("Close"))\n'),

    # A11Y005 — toggle
    ("A11Y005", True, 'Toggle(isOn: $on) { }\n'),
    ("A11Y005", False, 'Toggle(isOn: $on) { Text("Enable Face ID") }\n'),
    ("A11Y005", False, 'Toggle(isOn: $on) { }\n.accessibilityLabel(Text("Face ID"))\n'),

    # A11Y007 — Dynamic Type
    ("A11Y007", True, 'Text(x).font(.system(size: 15, weight: .medium))\n'),
    ("A11Y007", False,
     'Text(x).font(.system(size: 15, weight: .medium, relativeTo: .body))\n'),

    # A11Y008 — font shadowing
    ("A11Y008", True,
     'extension Font {\n    public static let body: Font = .system(size: 17)\n}\n'),
    ("A11Y008", False,
     'extension Font {\n    public static let subhead: Font = .system(size: 15)\n}\n'),

    # A11Y009 — unlocalized label
    ("A11Y009", True, 'Image(x).accessibilityLabel("Close")\n'),
    ("A11Y009", False,
     'Image(x).accessibilityLabel(NSLocalizedString("Close", comment: ""))\n'),
    ("A11Y009", False, 'Image(x).accessibilityLabel(Text(verbatim: "Dash"))\n'),

    # A11Y012 — tap gesture
    ("A11Y012", True, 'HStack { Text(name) }\n.onTapGesture { select() }\n'),
    ("A11Y012", False,
     'HStack { Text(name) }\n.accessibilityElement(children: .combine)\n'
     '.onTapGesture { select() }\n'),

    # Suppression comment
    ("A11Y004", False,
     '// a11y-ignore: A11Y004 decorative, the row above carries the label\n'
     'Button(action: onClose) {\n    Image(systemName: "xmark")\n}\n'),

    # Comments and strings must not trigger rules
    ("A11Y001", False,
     '// let item = UITabBarItem(title: nil, image: icon)\n'),
    ("A11Y004", False,
     'let doc = "Button(action: x) { Image(systemName: y) }"\n'),
]


def _config_fixtures() -> List[Tuple[str, bool, str, Dict[str, object]]]:
    """(rule, should_fire, source, config) — the tuning knobs must actually work."""
    icon_button = 'Button(action: x) {\n    Icon(name: .custom("icon_close"))\n}\n'
    font_ext = ('extension Font {\n'
                '    public static let body: Font = .system(size: 17)\n}\n')
    wrapper_use = 'DashStepper(count: $n, onChange: f)\n'
    return [
        # A component listed in labeled_wrappers is treated as announced.
        ("A11Y004", True, icon_button, {}),
        ("A11Y004", False,
         'Button(action: x) {\n    DashStepper(count: $n)\n}\n',
         {"labeled_wrappers": ["DashStepper"]}),
        ("A11Y004", False, wrapper_use, {}),
        # A deliberately kept shadow can be allowed by name.
        ("A11Y008", True, font_ext, {}),
        ("A11Y008", False, font_ext, {"allowed_font_shadows": ["body"]}),
        # Disabling a rule silences it entirely.
        ("A11Y004", False, icon_button, {"disabled_rules": ["A11Y004"]}),
    ]


def self_test() -> int:
    global CONFIG
    failures = 0

    for index, (rule_id, should_fire, source, cfg) in enumerate(
            _config_fixtures(), 1):
        saved = CONFIG
        CONFIG = Config(cfg)
        try:
            found = [f for f in _analyze_source(source)
                     if f.rule_id == rule_id
                     and f.rule_id not in CONFIG.disabled_rules]
        finally:
            CONFIG = saved
        if bool(found) != should_fire:
            failures += 1
            print("FAIL config#{:<2} {} with {} expected {}, got {}".format(
                index, rule_id, cfg or "{}",
                "a finding" if should_fire else "no finding",
                len(found)))

    for index, (rule_id, should_fire, source) in enumerate(FIXTURES, 1):
        found = [f for f in _analyze_source(source) if f.rule_id == rule_id]
        fired = bool(found)
        if fired != should_fire:
            failures += 1
            print("FAIL #{:<2} {} expected {}, got {}".format(
                index, rule_id,
                "a finding" if should_fire else "no finding",
                "{} finding(s)".format(len(found)) if fired else "none"))
            for line in source.strip().splitlines():
                print("         | {}".format(line))
    total = len(FIXTURES) + len(_config_fixtures())
    if failures:
        print("\n{}/{} fixtures failed".format(failures, total))
        return 1
    print("All {} rule and config fixtures pass".format(total))
    return 0


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Static VoiceOver / Dynamic Type audit for dashwallet-ios.")
    parser.add_argument("--repo-root", default=None,
                        help="defaults to the git root of this script")
    parser.add_argument("--path", action="append", default=None,
                        help="limit the scan to these paths (repeatable)")
    parser.add_argument("--rule", action="append", default=None,
                        help="only run these rules (repeatable)")
    parser.add_argument("--summary", action="store_true",
                        help="counts per rule, no individual findings")
    parser.add_argument("--json", metavar="FILE",
                        help="write the findings as JSON")
    parser.add_argument("--github", action="store_true",
                        help="emit GitHub Actions annotations")
    parser.add_argument("--baseline", default=BASELINE_PATH)
    parser.add_argument("--config", default=CONFIG_PATH,
                        help="project tuning file (optional)")
    parser.add_argument("--write-baseline", action="store_true",
                        help="record the current findings as accepted debt")
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if a finding is not in the baseline")
    parser.add_argument("--fail-on", default="P0,P1",
                        help="severities that fail --check (default: P0,P1). "
                             "New P2 findings are reported but do not block.")
    parser.add_argument("--list-rules", action="store_true")
    parser.add_argument("--self-test", action="store_true",
                        help="run the rule fixtures and exit")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    if args.list_rules:
        for rule_id in sorted(RULES, key=lambda r: (SEVERITY_ORDER[RULES[r].severity], r)):
            rule = RULES[rule_id]
            print("{:<9} {:<4} {}".format(rule_id, rule.severity, rule.title))
            print("{:>14} {}".format("fix:", rule.fix))
        return 0

    repo_root = args.repo_root
    if repo_root is None:
        here = os.path.dirname(os.path.abspath(__file__))
        repo_root = os.path.dirname(here)
    repo_root = os.path.abspath(repo_root)

    roots = args.path if args.path else SCAN_ROOTS
    enabled = set(args.rule) if args.rule else None
    if enabled:
        unknown = enabled - set(RULES)
        if unknown:
            print("Unknown rule(s): {}".format(", ".join(sorted(unknown))),
                  file=sys.stderr)
            return 2

    global CONFIG
    CONFIG = load_config(repo_root, args.config)

    findings = analyze(repo_root, roots, enabled)

    if args.write_baseline:
        write_baseline(repo_root, args.baseline, findings)
        print("Wrote {} findings to {}".format(len(findings), args.baseline))
        return 0

    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump({"total": len(findings),
                       "counts": dict(Counter(f.rule_id for f in findings)),
                       "findings": [f.to_dict() for f in findings]},
                      handle, indent=2, ensure_ascii=False)
            handle.write("\n")

    if args.check:
        baseline = load_baseline(repo_root, args.baseline)
        if baseline is None:
            print("No baseline at {} — run --write-baseline first."
                  .format(args.baseline), file=sys.stderr)
            return 2
        new = [f for f in findings if f.key() not in baseline]
        current_keys = {f.key() for f in findings}
        fixed = len(baseline - current_keys)

        blocking_severities = {s.strip().upper()
                               for s in args.fail_on.split(",") if s.strip()}
        if "ALL" in blocking_severities:
            blocking_severities = set(SEVERITY_ORDER)
        def blocks(f: "Finding") -> bool:
            if f.rule_id in CONFIG.advisory_rules:
                return False
            return f.severity in blocking_severities

        blocking = [f for f in new if blocks(f)]
        advisory = [f for f in new if not blocks(f)]

        if args.github:
            print_github(new)

        for label, group in (("BLOCKING", blocking), ("advisory", advisory)):
            if not group:
                continue
            print("{} — {} new accessibility finding(s):".format(
                label, len(group)))
            for f in group:
                print("  [{}] {} {}:{}".format(
                    f.severity, f.rule_id, f.path, f.line))
                if f.detail:
                    print("        {}".format(f.detail))
                print("        fix: {}".format(RULES[f.rule_id].fix))
            print()

        if blocking:
            print("If a finding is a deliberate exception, annotate the line:")
            print("  // a11y-ignore: <RULE> <why>")
            print("Never regenerate the baseline to silence a new finding.")
            return 1

        message = "No new blocking accessibility findings ({} known)".format(
            len(findings))
        if fixed:
            message += " — {} baseline entr{} fixed, run --write-baseline " \
                       "to bank the progress".format(
                           fixed, "y" if fixed == 1 else "ies")
        print(message)
        return 0

    if args.github:
        print_github(findings)
    else:
        print_report(findings, args.summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
