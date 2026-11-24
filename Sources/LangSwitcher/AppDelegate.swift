import AppKit
import ApplicationServices
import Carbon
import ServiceManagement
import SwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let layouts = KeyboardLayouts()
    private var word = TypedWord()
    private var tap = ModifierTap()
    private var shortcuts = Shortcut.restore(
        saved: UserDefaults.standard.stringArray(forKey: "shortcuts"),
        legacy: UserDefaults.standard.string(forKey: "shortcut")
    )
    private var field: TextField?
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var timer: Timer?
    private var status: NSStatusItem!
    private var revision = 0
    private var pendingEdit: PasteEdit?
    private var waitingToQuit = false
    private var history: (cycle: ConversionCycle, range: NSRange)?
    private var gestureField: TextField?
    private var focusObserver: AXObserver?
    private var observedPID: pid_t?
    private var monitorError = false
    private var accessibilityRestart = AccessibilityRestart(initiallyTrusted: AXIsProcessTrusted())

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy must never install another tap and convert the same word twice.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.imagePosition = .imageOnly
        status.button?.imageScaling = .scaleNone
        status.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        updateMenu()
        startIfPermitted()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if self.eventTap == nil, trusted { self.startIfPermitted() }
            self.checkFocus()
            if self.accessibilityRestart.observe(trusted: trusted) {
                AccessibilityRestart.showPrompt()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(sourceChanged), name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(sourceChanged), name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String), object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelPendingEdit()
        timer?.invalidate()
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        if let focusObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(focusObserver), .commonModes) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let pendingEdit, pendingEdit.waitingForPaste else { return .terminateNow }
        waitingToQuit = true
        pendingEdit.cancel()
        return .terminateLater
    }

    private func startIfPermitted() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: pointer) else {
            monitorError = true
            updateMenu()
            return
        }
        eventTap = port
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let eventSource { CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        CGEvent.tapEnable(tap: port, enable: true)
        monitorError = false
        updateMenu()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == PasteEdit.eventMarker { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn])
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown || type == .scrollWheel {
            tap.cancel()
            reset()
            return false
        }
        if type == .flagsChanged {
            checkFocus()
            guard let shortcut = shortcuts.first(where: { $0.keyCode == code }) else {
                tap.cancel()
                gestureField = nil
                return false
            }
            if shortcut.isPressed(with: event.flags) {
                gestureField = field
                let alone = flags == shortcut.modifier && field != nil
                    && !shortcut.isOtherSideDown(with: event.flags)
                tap.press(keyCode: code, alone: alone,
                          otherKeysDown: otherKeysDown(excluding: code), mouseDown: mouseDown())
            } else {
                if tap.release(keyCode: code), let gestureField {
                    scheduleConversion(for: gestureField)
                }
                gestureField = nil
            }
            return false
        }
        guard type == .keyDown else { return false }
        tap.cancel()
        pendingEdit?.beforeUserKey()
        revision += 1
        history = nil
        checkFocus()
        guard let field, let selection = field.selection, !IsSecureEventInputEnabled() else { reset(); return false }
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty { reset(); return false }
        if selection.length > 0 { word.reset() }
        if code == 51 { word.backspace(at: selection.location); return false }
        // Navigation, Escape, Return and Tab invalidate the suffix, not the application's key.
        if [36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(code) {
            reset()
            return false
        }
        guard let sourceID = layouts.currentID,
              let text = NSEvent(cgEvent: event)?.characters, !text.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { reset(); return false }
        let stroke = KeyboardStroke(key: UInt16(code), shift: event.flags.contains(.maskShift),
                                    capsLock: event.flags.contains(.maskAlphaShift))
        word.append(text, sourceID: sourceID, at: selection.location, stroke: stroke)
        return false
    }

    private func checkFocus() {
        let current = TextAccess.focusedField()
        let same = field.flatMap { old in current.map { old.same(as: $0) } } ?? (field == nil && current == nil)
        if !same { reset() }
        field = current
        if let current, observedPID != current.pid { observeFocus(in: current.pid) }
    }

    private func reset() {
        cancelPendingEdit()
        word.reset()
        history = nil
        tap.cancel()
        gestureField = nil
        revision += 1
    }

    private func cancelPendingEdit() {
        pendingEdit?.cancel()
    }

    private func otherKeysDown(excluding code: Int64) -> Bool {
        (0..<128).contains { key in
            key != code && key != 57 && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(key))
        }
    }

    private func mouseDown() -> Bool {
        (0..<32).contains { CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) }
    }

    private func observeFocus(in pid: pid_t) {
        if let focusObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(focusObserver), .commonModes) }
        focusObserver = nil
        observedPID = pid
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, name, pointer in
            guard let pointer else { return }
            let owner = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            if name as String == kAXFocusedWindowChangedNotification {
                owner.applicationChanged()
            } else {
                // A delayed notification for the same field should not discard newly typed keys.
                owner.checkFocus()
            }
        }, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXFocusedUIElementChangedNotification as CFString, pointer)
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, pointer)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        focusObserver = observer
    }

    private func scheduleConversion(for expectedField: TextField) {
        guard pendingEdit == nil else { return }
        let triggeredAt = revision
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingEdit == nil, self.revision == triggeredAt,
                  self.stillFocused(expectedField),
                  let snapshot = expectedField.snapshot(revision: triggeredAt) else { return }
            self.convert(field: expectedField, snapshot: snapshot)
        }
    }

    private func convert(field: TextField, snapshot: EditSnapshot) {
        guard !field.isSecure, stillFocused(field), revision == snapshot.revision else { return }
        layouts.refresh()
        let selection = snapshot.selection
        var range: NSRange
        var cycle: ConversionCycle
        var isWord = false
        if let previous = history,
           (selection == previous.range || selection == NSRange(location: NSMaxRange(previous.range), length: 0)),
           let stringRange = Range(previous.range, in: snapshot.text),
           String(snapshot.text[stringRange]) == previous.cycle.text {
            range = previous.range
            cycle = previous.cycle
            isWord = !word.text.isEmpty
        } else if selection.length > 0, let selectedRange = Range(selection, in: snapshot.text) {
            let selected = String(snapshot.text[selectedRange])
            guard !selected.isEmpty, selected.utf16.count <= 100_000,
                  let source = layouts.inferredSource(for: selected, preferredID: layouts.currentID) else { return }
            range = selection
            cycle = ConversionCycle(text: selected, sourceID: source.id)
        } else {
            guard selection.length == 0, word.expectedCaret == selection.location,
                  let sourceID = word.sourceID,
                  let wordRange = lastWordRange(in: snapshot.text, caret: selection.location, matchingRecent: word.text),
                  let stringRange = Range(wordRange, in: snapshot.text) else { reset(); return }
            range = wordRange
            let fullWord = String(snapshot.text[stringRange])
            let missingStrokes = max(0, fullWord.count - word.strokes.count)
            let strokes = Array<KeyboardStroke?>(repeating: nil, count: missingStrokes) + word.strokes
            cycle = ConversionCycle(text: fullWord, sourceID: sourceID, strokes: strokes)
            isWord = true
        }
        guard let target = cycle.advance(in: layouts.enabled) else { return }
        guard let edit = PasteEdit(field: field, snapshot: snapshot, range: range, replacement: cycle.text,
                                   stillFocused: { [weak self] in
            guard let self else { return false }
            return self.revision == snapshot.revision && self.stillFocused(field)
        }, completion: { [weak self] result in
            guard let self else { return }
            self.pendingEdit = nil
            if self.waitingToQuit {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            if result == .cancelled { return }
            guard result == .pasted, self.layouts.select(target) else {
                self.reset()
                NSSound.beep()
                return
            }
            let newRange = NSRange(location: range.location, length: cycle.text.utf16.count)
            if isWord {
                self.word.replace(with: cycle.text, sourceID: target.id,
                                  caret: NSMaxRange(newRange), strokes: cycle.strokes)
            } else {
                self.word.reset()
            }
            self.history = (cycle, newRange)
        }) else { return }
        pendingEdit = edit
        edit.start()
    }

    private func stillFocused(_ expected: TextField) -> Bool {
        guard let current = TextAccess.focusedField() else { return false }
        return current.same(as: expected) && !current.isSecure
    }

    @objc private func applicationChanged() { tap.cancel(); reset(); field = nil }
    @objc private func sourceChanged() {
        layouts.refresh()
        if let sourceID = word.sourceID, sourceID != layouts.currentID { reset() }
        if let history, history.cycle.sourceID != layouts.currentID { reset() }
    }

    func menuWillOpen(_ menu: NSMenu) { updateMenu() }

    private func updateMenu() {
        guard let menu = status?.menu else { return }
        menu.removeAllItems()
        let trusted = AXIsProcessTrusted()
        let canPost = trusted && CGPreflightPostEventAccess()
        let label: String
        if !trusted {
            label = NSLocalizedString("status.accessibility", comment: "")
        } else if monitorError {
            label = NSLocalizedString("status.keyboard", comment: "")
        } else if !canPost {
            label = NSLocalizedString("status.paste", comment: "")
        } else if shortcuts.count == 1, let shortcut = shortcuts.first {
            label = String.localizedStringWithFormat(NSLocalizedString("status.ready", comment: ""), shortcut.title)
        } else {
            label = String.localizedStringWithFormat(NSLocalizedString("status.readyMultiple", comment: ""), shortcuts.count)
        }
        menu.addItem(withTitle: label, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        if !canPost || monitorError {
            addItem(NSLocalizedString("menu.configureAccess", comment: ""), action: #selector(configurePermissions), to: menu)
            menu.addItem(.separator())
        }
        layouts.refresh()
        let languageMenu = NSMenu()
        for layout in layouts.enabled {
            let item = NSMenuItem(title: layout.name, action: nil, keyEquivalent: "")
            item.state = layout.id == layouts.currentID ? .on : .off
            languageMenu.addItem(item)
        }
        if layouts.enabled.count < 2 {
            languageMenu.addItem(withTitle: NSLocalizedString("menu.addLayout", comment: ""), action: nil, keyEquivalent: "")
        }
        let languages = NSMenuItem(title: NSLocalizedString("menu.systemLayouts", comment: ""), action: nil, keyEquivalent: "")
        languages.submenu = languageMenu
        menu.addItem(languages)
        let shortcutMenu = NSMenu()
        shortcutMenu.autoenablesItems = false
        for choice in Shortcut.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(toggleShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            let selected = shortcuts.contains(choice)
            item.state = selected ? .on : .off
            item.isEnabled = !selected || shortcuts.count > 1
            shortcutMenu.addItem(item)
        }
        let shortcutItem = NSMenuItem(title: NSLocalizedString("menu.shortcut", comment: ""), action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)
        let login = addItem(NSLocalizedString("menu.launchAtLogin", comment: ""), action: #selector(toggleLogin), to: menu)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        addItem(NSLocalizedString("menu.about", comment: ""), action: #selector(about), to: menu)
        addItem(NSLocalizedString("menu.quit", comment: ""), action: #selector(quit), to: menu)
        status.button?.toolTip = "LangSwitcher — \(label)"
        status.button?.setAccessibilityLabel("LangSwitcher. \(label)")
    }

    @discardableResult private func addItem(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggleShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = Shortcut(rawValue: raw) else { return }
        if shortcuts.contains(choice) {
            guard shortcuts.count > 1 else { return }
            shortcuts.remove(choice)
        } else {
            shortcuts.insert(choice)
        }
        let saved = Shortcut.allCases.filter(shortcuts.contains).map(\.rawValue)
        UserDefaults.standard.set(saved, forKey: "shortcuts")
        reset()
        updateMenu()
    }

    @objc private func configurePermissions() {
        let anchor: String
        if !AXIsProcessTrusted() {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [promptKey: true] as CFDictionary
            guard !AXIsProcessTrustedWithOptions(options) else { return }
            anchor = "Privacy_Accessibility"
        } else if monitorError {
            if CGRequestListenEventAccess() {
                startIfPermitted()
                return
            }
            anchor = "Privacy_ListenEvent"
        } else {
            guard !CGPreflightPostEventAccess(), !CGRequestPostEventAccess() else { return }
            anchor = "Privacy_Accessibility"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("login.failure", comment: "")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        updateMenu()
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "LangSwitcher"
        alert.informativeText = NSLocalizedString("about.instructions", comment: "")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
