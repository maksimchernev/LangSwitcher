# LangSwitcher

<img src="Resources/AppIcon.png" alt="LangSwitcher icon with A and Я keys" width="96">

Fix text typed with the wrong keyboard layout on macOS. Type `ghbdtn`, then tap and release **left Option (⌥)**. LangSwitcher replaces it with `привет` and switches your keyboard to Russian so you can keep typing.

LangSwitcher lives in the menu bar and runs on demand. It uses the keyboard layouts already enabled in macOS. The interface follows your preferred languages in macOS and defaults to English when neither English nor Russian is preferred.

[**Download LangSwitcher.dmg**](https://github.com/maksimchernev/LangSwitcher/releases/latest/download/LangSwitcher.dmg). Open the disk image and drag LangSwitcher into **Applications**.

## Build and install

The app runs on **Apple silicon** with **macOS 13 or later**. Building requires **Swift 6** and the **macOS 15.4 SDK or later**, available with Xcode or Xcode Command Line Tools.

```sh
git clone https://github.com/maksimchernev/LangSwitcher.git
cd LangSwitcher
bash scripts/build.sh
```

1. Move `dist/LangSwitcher.app` to **Applications** and open it.
2. Choose **Set Up Access…** in the LangSwitcher menu and enable LangSwitcher in **System Settings → Privacy & Security → Accessibility**. Choose **Restart** when LangSwitcher offers to restart.
3. If the menu says it still needs keyboard access, choose **Set Up Access…** again and enable LangSwitcher under **Privacy & Security → Input Monitoring**, then quit and reopen it.
4. Make sure at least two keyboard layouts are enabled under **System Settings → Keyboard → Text Input → Edit**. The **System Layouts** submenu lists the layouts LangSwitcher can use.

The app is signed locally during the build. After replacing an older build, quit it and open the new copy. If macOS still reports missing access, remove the old LangSwitcher entry from Accessibility and add the new app. Look for the **A** and **Я** keys in the menu bar. The menu shows the current permission status.

## Use it

| To fix… | What to do |
| --- | --- |
| The last word you typed | Tap and release left Option. Spaces you already typed after the word stay in place. |
| Part of a word, a phrase, or multiple lines | Select the text first, then tap left Option. |
| The same text again | Tap left Option again before editing or leaving the field. With two layouts, this restores the original text and input language. |

With more than two layouts, repeated taps cycle through the layouts that change the text. Option shortcuts such as **⌥←** still work as usual. Choose one or more keys under **Correction Keys**. Tap any one of them to make a correction. Use **Launch at Login** to start LangSwitcher at login.

## Compatibility and privacy

LangSwitcher uses macOS Accessibility to verify the focused field and selection, then replaces the range with the editor's normal paste command. If the field or range cannot be verified, the shortcut skips the edit. Formatting follows the editor's plain-text paste behavior. Password fields, secure input, and composition-based input methods are skipped.

Text is processed on your Mac. Recent input is held in memory while the field is focused. LangSwitcher temporarily puts the replacement on the clipboard, then restores your previous contents on this Mac or clears the clipboard if it was empty. It checks for newer clipboard contents before writing or restoring. If macOS asks for paste access, it is needed to save and restore the clipboard. The edit is skipped if the original contents cannot be saved.

## Checks

```sh
bash scripts/check.sh
dist/LangSwitcher.app/Contents/MacOS/LangSwitcher --diagnose
```

The checks cover word boundaries, shortcut handling, layout conversion, and restoration of isolated test clipboards. The diagnostic command prints the available layouts and whether macOS lets the process use Accessibility and post input events. If a particular app has trouble, include its name, your macOS version, and a sample you can share when [opening an issue](https://github.com/maksimchernev/LangSwitcher/issues/new).
