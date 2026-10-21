import Foundation

/// The app's own settings, stored in its own preferences file
/// (~/Library/Preferences/com.matejbasic.NaturalScrollToggle.plist).
/// Read them in a terminal with `defaults read com.matejbasic.NaturalScrollToggle`.
enum Settings {
    static let domain = "com.matejbasic.NaturalScrollToggle"

    /// The app's own UserDefaults. When the binary runs inside the .app
    /// bundle, `.standard` already is that domain. When it runs some other
    /// way, the domain is named explicitly so the same file is used.
    private static let store: UserDefaults = {
        if Bundle.main.bundleIdentifier == domain {
            return .standard
        }
        return UserDefaults(suiteName: domain) ?? .standard
    }()

    private enum Key {
        static let autoSwitchEnabled = "autoSwitchEnabled"
        static let ignoredDeviceKeys = "ignoredDeviceKeys"
        static let rememberedNaturalScrolling = "rememberedNaturalScrolling"
    }

    /// "Switch off automatically when a mouse is connected". Off by default.
    static var autoSwitchEnabled: Bool {
        get { store.bool(forKey: Key.autoSwitchEnabled) }
        set { store.set(newValue, forKey: Key.autoSwitchEnabled) }
    }

    /// Devices unticked in the "Pointing devices" menu, by `PointingDevice.key`.
    static var ignoredDeviceKeys: Set<String> {
        get { Set(store.stringArray(forKey: Key.ignoredDeviceKeys) ?? []) }
        set { store.set(newValue.sorted(), forKey: Key.ignoredDeviceKeys) }
    }

    /// The natural scrolling setting from just before the first mouse
    /// appeared, or nil when nothing is remembered.
    static var rememberedNaturalScrolling: Bool? {
        get { store.object(forKey: Key.rememberedNaturalScrolling) as? Bool }
        set {
            if let newValue {
                store.set(newValue, forKey: Key.rememberedNaturalScrolling)
            } else {
                store.removeObject(forKey: Key.rememberedNaturalScrolling)
            }
        }
    }
}
