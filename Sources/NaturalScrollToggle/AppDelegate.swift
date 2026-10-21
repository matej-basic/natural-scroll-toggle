import AppKit
import ScrollCore
import ServiceManagement

/// Owns the menu bar icon and its menu, and applies automatic switching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let mouseMonitor = MouseMonitor()
    /// Devices present right now. Stays nil until the monitor has reported
    /// once, so the app does not act on an empty list at startup.
    private var devices: [PointingDevice]?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The status item is the icon that lives in the menu bar.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        mouseMonitor.onChange = { [weak self] devices in
            self?.devices = devices
            self?.applyAutoSwitch()
        }
        mouseMonitor.start()

        refresh()
        observeSystemChanges()
    }

    // MARK: Automatic switching

    /// Asks the policy what natural scrolling should be and applies it.
    private func applyAutoSwitch() {
        guard let devices else { return }
        let policy = AutoSwitchPolicy(isEnabled: Settings.autoSwitchEnabled, ignoredKeys: Settings.ignoredDeviceKeys)
        let current = NaturalScrolling.isEnabled
        let decision = policy.decide(
            presentDevices: devices,
            current: current,
            rememberedBeforeMouse: Settings.rememberedNaturalScrolling
        )
        Settings.rememberedNaturalScrolling = decision.rememberedBeforeMouse
        if decision.naturalScrolling != current {
            NaturalScrolling.isEnabled = decision.naturalScrolling
        }
        refresh()
    }

    // MARK: Menu

    /// Rebuilds the menu and the icon from the current state.
    func refresh() {
        let on = NaturalScrolling.isEnabled

        // SF Symbols are icons built into macOS. Two different symbols make
        // the state visible at a glance.
        let symbol = on ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Natural scrolling \(on ? "on" : "off")")
        image?.isTemplate = true  // lets macOS tint it for light/dark menu bars
        statusItem.button?.image = image

        let menu = NSMenu()

        let toggleItem = item("Natural scrolling", action: #selector(toggleScrolling))
        toggleItem.state = on ? .on : .off
        menu.addItem(toggleItem)

        // Only shown when the app can write the preference but cannot apply it.
        if NaturalScrolling.backend == .preferencesOnly {
            let warning = NSMenuItem(title: "Warning: changes apply after the next login", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            statusItem.button?.toolTip = "Toggle backend: \(NaturalScrolling.backend.rawValue). Changes apply after the next login."
        } else {
            statusItem.button?.toolTip = nil
        }

        menu.addItem(.separator())

        let autoItem = item("Switch off automatically when a mouse is connected", action: #selector(toggleAutoSwitch))
        autoItem.state = Settings.autoSwitchEnabled ? .on : .off
        menu.addItem(autoItem)

        let devicesItem = NSMenuItem(title: "Pointing devices", action: nil, keyEquivalent: "")
        devicesItem.submenu = devicesMenu()
        menu.addItem(devicesItem)

        menu.addItem(launchAtLoginItem())

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    /// The "Pointing devices" submenu: external mice you can tick or untick,
    /// then, greyed out, the devices the filter rejected.
    private func devicesMenu() -> NSMenu {
        let menu = NSMenu()
        let present = devices ?? []
        let ignored = Settings.ignoredDeviceKeys

        let mice = present.filter(\.isExternalMouse)
        if mice.isEmpty {
            let none = NSMenuItem(title: "No external mouse detected", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for device in mice {
            let deviceItem = item(device.displayName, action: #selector(toggleDeviceIgnored(_:)))
            deviceItem.representedObject = device.key
            deviceItem.state = ignored.contains(device.key) ? .off : .on
            deviceItem.toolTip = "Ticked devices count as a connected mouse."
            menu.addItem(deviceItem)
        }

        let rejected = present.filter { !$0.isExternalMouse }
        if !rejected.isEmpty {
            menu.addItem(.separator())
            // Several HID objects can share a name; list each name once.
            var shown = Set<String>()
            for device in rejected {
                let title = "\(device.displayName) (\(device.rejectionReason ?? "rejected"))"
                guard shown.insert(title).inserted else { continue }
                let rejectedItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                rejectedItem.isEnabled = false
                menu.addItem(rejectedItem)
            }
        }
        return menu
    }

    /// "Launch at login", using the system's login item service.
    private func launchAtLoginItem() -> NSMenuItem {
        let launchItem = item("Launch at login", action: #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled:
            launchItem.state = .on
        case .requiresApproval:
            // Registered, but the user still has to allow it in
            // System Settings > General > Login Items.
            launchItem.state = .on
            launchItem.title = "Launch at login (approve in System Settings)"
        default:
            launchItem.state = .off
        }
        return launchItem
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    // MARK: Menu actions

    @objc private func toggleScrolling() {
        NaturalScrolling.toggle()
        refresh()
    }

    @objc private func toggleAutoSwitch() {
        Settings.autoSwitchEnabled.toggle()
        applyAutoSwitch()
        refresh()
    }

    @objc private func toggleDeviceIgnored(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        var ignored = Settings.ignoredDeviceKeys
        if ignored.contains(key) {
            ignored.remove(key)
        } else {
            ignored.insert(key)
        }
        Settings.ignoredDeviceKeys = ignored
        applyAutoSwitch()
        refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            logError("launch at login: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    // MARK: Changes made elsewhere

    /// Listens for the system notification so the menu stays correct when the
    /// setting is changed in System Settings (or by anything else).
    private func observeSystemChanges() {
        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
                // Notifications may arrive off the main thread; UI work must run on it.
                DispatchQueue.main.async { delegate.refresh() }
            },
            NaturalScrolling.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }
}
