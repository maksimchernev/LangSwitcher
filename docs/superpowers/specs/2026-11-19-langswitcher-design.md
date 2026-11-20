# LangSwitcher

Approved in chat on 2026-11-19: a native Apple Silicon macOS menu-bar utility.

- A standalone left Option tap converts the selected editable text, otherwise the most recently typed word in the currently focused field. Combinations with any key/modifier/click must remain normal.
- A word is the text after the preceding whitespace; the first word starts at the start of typing. Trailing spaces are retained when converting the preceding word.
- Use enabled system keyboard layouts, including their punctuation, Shift, Caps Lock and ё mappings. Switch the system input source to the conversion's target.
- Repeated taps cycle the same text and input language until another edit. Clear all tracked text/history when the field loses focus; never edit a stale target.
- Retain the system clipboard, surrounding text, text style and cursor. Skip password fields and secure input.
- Menu: status, change shortcut, launch at login, quit. No automatic corrections.

## Approach

A native Swift/AppKit app uses a keyboard event tap, the Accessibility API for focused-field/selection validation and replacement, and Carbon Text Input Sources/UCKeyTranslate for system layout mappings. Recent input is kept only in memory. Edits target an exact AX element and verified range without using the clipboard or global synthetic deletion/typing. A field that does not support AXSelectedText writes is skipped. Dependencies beyond Apple's frameworks are unnecessary; scripting wrappers add installation and permission complexity.

Only layouts that expose a Unicode keyboard map can participate in character-for-character conversion. Composition-based input methods (e.g. Chinese IMEs) cannot be converted as a direct keyboard layout. With more than two layouts, use the enabled system order and cycle forward, skipping equivalent translations. Focus loss, cursor movement, paste, undo and unsupported editing commands invalidate tracked input. Selected text is read afresh each time. Preserve actual key strokes for typed words and exact text snapshots for each visited layout so ambiguous mappings round-trip correctly.

## Validation

Automated checks cover word boundaries, backspace, repeated conversions, modifier/combination detection and actual installed layout mappings. Build a signed local .app. Verify the menu and available test flows with native UI if system permissions allow; explicitly report any untested cross-application behavior.
