import Foundation

/// How the app changes the setting. Picked once, the first time it is needed.
enum ToggleBackend: String {
    /// The private function System Settings itself calls. Applies immediately.
    case preferencePanesSupport = "PreferencePanesSupport"
    /// An older private function in the window server. Fallback.
    case cgs = "CGS"
    /// Only the preference file is written. Per the sources in
    /// docs/RESEARCH.md, scrolling then changes at the next login only.
    case preferencesOnly = "preferences only"
}

/// Reads and writes the macOS "natural scrolling" preference.
///
/// macOS stores this as a Bool under the key `com.apple.swipescrolldirection`
/// in the global preference domain (the same place `defaults write -g` uses).
/// Writing that value alone does not change how scrolling behaves until the
/// next login. To apply it right away, the app calls the same private
/// function System Settings uses, found at run time with dlopen/dlsym so the
/// app still starts if a future macOS removes it.
enum NaturalScrolling {
    /// The preference key in the global domain.
    static let key = "com.apple.swipescrolldirection" as CFString

    /// Name of the system-wide notification macOS uses to announce a change.
    /// System Settings and this app listen for it to update their checkboxes.
    static let notificationName = "SwipeScrollDirectionDidChangeNotification"

    // MARK: Private functions, looked up once

    /// `void setSwipeScrollDirection(bool)` in PreferencePanesSupport.
    private typealias SetSwipeScrollDirection = @convention(c) (Bool) -> Void
    /// `int _CGSDefaultConnection(void)` in SkyLight.
    private typealias CGSDefaultConnection = @convention(c) () -> Int32
    /// `CGError CGSSetSwipeScrollDirection(int connection, bool)` in SkyLight.
    private typealias CGSSetSwipeScrollDirection = @convention(c) (Int32, Bool) -> Int32

    /// Looks up a C function in a system framework. Returns nil if the
    /// framework or the symbol is missing.
    private static func lookUp(_ symbol: String, in path: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        return dlsym(handle, symbol)
    }

    private static let preferencePanesSetter: SetSwipeScrollDirection? = {
        let path = "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"
        guard let pointer = lookUp("setSwipeScrollDirection", in: path) else { return nil }
        return unsafeBitCast(pointer, to: SetSwipeScrollDirection.self)
    }()

    private static let cgsSetter: ((Bool) -> Void)? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let connectionPointer = lookUp("_CGSDefaultConnection", in: path),
            let setterPointer = lookUp("CGSSetSwipeScrollDirection", in: path)
        else { return nil }
        let connection = unsafeBitCast(connectionPointer, to: CGSDefaultConnection.self)
        let setter = unsafeBitCast(setterPointer, to: CGSSetSwipeScrollDirection.self)
        return { natural in
            let error = setter(connection(), natural)
            if error != 0 {
                logError("CGSSetSwipeScrollDirection returned error \(error)")
            }
        }
    }()

    /// Which way of applying the setting is available on this Mac.
    static let backend: ToggleBackend = {
        if preferencePanesSetter != nil { return .preferencePanesSupport }
        if cgsSetter != nil { return .cgs }
        return .preferencesOnly
    }()

    // MARK: Reading and writing

    /// True when natural scrolling is on. A missing key counts as on,
    /// because that is the macOS default.
    static var isEnabled: Bool {
        get {
            // Make sure we see what other processes (System Settings) wrote.
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            let value = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            guard let number = value as? Bool else { return true }
            return number
        }
        set {
            // 1. Apply the change to the running system.
            switch backend {
            case .preferencePanesSupport:
                preferencePanesSetter?(newValue)
            case .cgs:
                cgsSetter?(newValue)
            case .preferencesOnly:
                break
            }

            // 2. Write the preference too. The private function already does
            //    this, but writing it again is harmless and keeps
            //    `defaults read -g com.apple.swipescrolldirection` correct
            //    when only the fallback is available.
            //    Never use UserDefaults.standard here: that writes the app's
            //    own settings, not the global one.
            CFPreferencesSetValue(
                key,
                (newValue ? kCFBooleanTrue : kCFBooleanFalse),
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

            // 3. Tell System Settings and other listening apps.
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDistributedCenter(),
                CFNotificationName(notificationName as CFString),
                nil,
                nil,
                true
            )

            // 4. Check that the value stuck.
            let readBack = isEnabled
            if readBack != newValue {
                logError("natural scrolling set to \(newValue) but reads back as \(readBack) (backend: \(backend.rawValue))")
            }
        }
    }

    /// Flips the setting and returns the new value.
    @discardableResult
    static func toggle() -> Bool {
        isEnabled.toggle()
        return isEnabled
    }
}

/// Writes a message to standard error, which ends up in Console.app for the
/// menu bar app and in the terminal for the command line options.
func logError(_ message: String) {
    FileHandle.standardError.write(Data("NaturalScrollToggle: \(message)\n".utf8))
}
