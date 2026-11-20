# Execution ledger — plan: docs/superpowers/plans/2026-11-19-langswitcher.md

- Task 1 complete: bounded typed-word state, standalone modifier handling, real system layout translation, repeat conversion snapshots. Stubs were tested RED before implementations; final checks: 16 scenarios, zero failures.
- Task 2 complete for source and local packaging: native AppKit utility, permission status, shortcut choices, login toggle, release arm64 .app with local signature.
- Ruling: use the current empty checkout on codex/native-switcher rather than create a second worktree; there were no existing files or commits to isolate.
- Ruling: Command Line Tools have no XCTest module. Use a runnable Swift check target with assertions and nonzero failure exit code, without third-party test frameworks.
- Independent review: /root/review_native_switcher, 2026-11-20. Identified stale-focus edits, unverified global deletion, unanchored typed suffix, previously held keys/buttons/Fn, Caps Lock ambiguity, inexact reverse conversion and equivalent-layout blocking.
- Fixed with RED→GREEN regression checks: EditSnapshot rejects changed revision/value/selection; TypedWord anchors expected caret; ModifierTap rejects held keys/buttons; ConversionCycle caches original variants and skips equivalent layouts; real physical strokes preserve Caps Lock punctuation.
- Ruling: replace global synthetic deletion/typing with a targeted AXSelectedText write after exact value/range/focus validation. This reduces compatibility with fields that do not support native AX replacement, but prevents blind deletion of unrelated text. Unsupported fields fail closed.
- Added focused-element/window AX observers in addition to app notifications and polling, and cancel modifier gestures on resets.
- Remaining verification: no live UI flow, Telegram/browser/code-editor compatibility, mixed rich-text formatting or login-service behavior verified. CUA connection expired and a fresh session timed out. Application diagnostic reports Accessibility not granted. User must grant the OS permission before external input tests are possible.
- No deferred minor review findings. IME composition methods remain outside direct keyboard-layout conversion as documented in the spec.
