# LangSwitcher Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, followed by one fresh reviewer. Steps use checkbox syntax.

**Goal:** Convert a typed word or selected text with a left Option tap and switch the system input language.

**Architecture:** A small testable core handles input history, modifier taps and system layout mapping. An AppKit menu-bar executable validates the focused field and performs native text replacement.

**Tech Stack:** Swift 6 compiler in Swift 5 language mode, Swift Package Manager, AppKit, ApplicationServices, Carbon, ServiceManagement. No external packages.

**Spec:** `docs/superpowers/specs/2026-11-19-langswitcher-design.md`

## Global Constraints

- macOS 13+, native arm64 build; enabled system keyboard layouts.
- Default shortcut is left Option alone; combinations keep their usual action.
- No clipboard writes, no text persistence, no automatic conversion.
- Reset typing history on focus loss, pointer editing, navigation and other untracked edits.
- Never edit a secure/read-only field or a stale target.

## Review Focus

- Focus changes between shortcut release and replacement must cancel the edit.
- Shift/Caps Lock and punctuation must use actual layout maps.
- Trailing whitespace and backspace must retain the correct token.
- A modifier used in a combination or click must not fire on release.
- Selection replacement and repeated conversion must preserve surrounding text and language state.

### Task 1: Core and system layouts

Files: `Sources/SwitcherCore/InputState.swift`, `Sources/SwitcherCore/KeyboardLayouts.swift`, `Tests/SwitcherCoreTests/CoreTests.swift`.

Produces `TypedWord` (append/backspace/reset/replace), `ModifierTap` (press/cancel/release), and `KeyboardLayouts` (enabled/current/convert/select).

- [x] Write behavior tests with literal expected words and shortcut sequences; run against stubs and observe failures.
- [x] Implement bounded input history and standalone modifier detection; run the full suite.
- [x] Test conversion with real enabled system layouts; implement UCKeyTranslate conversion and input-source selection; run the full suite.

### Task 2: Native utility and packaging

Files: `Sources/LangSwitcher/main.swift`, `Sources/LangSwitcher/AppDelegate.swift`, `Sources/LangSwitcher/TextAccess.swift`, `scripts/build.sh`, `Resources/Info.plist`, `README.md`.

Consumes the core interfaces above. Produces `dist/LangSwitcher.app` with a menu, permissions status, shortcut choices and launch at login.

- [x] Implement event tap, focus/secure-input validation, selected text replacement, recent-word conversion and input-source synchronization.
- [x] Build release .app and verify bundle metadata, architecture and signature.
- [x] Run all tests and the app's diagnostic command. Native UI inspection attempted but connection unavailable; Accessibility permission not granted.
- [x] Obtain one independent code review, fix material findings, rerun verification, and document remaining live-app verification limits.
