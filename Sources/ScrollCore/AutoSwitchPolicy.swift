import Foundation

/// The rule for automatic switching, written as a pure function so it can be
/// tested without a Mac or a mouse.
///
/// - While at least one counted mouse is present, natural scrolling is off.
/// - When the first mouse appears, the setting the user had just before is
///   remembered.
/// - When the last mouse goes away, the remembered setting comes back
///   (natural scrolling on, the macOS default, if nothing was remembered).
public struct AutoSwitchPolicy: Equatable, Sendable {
    /// Whether automatic switching is turned on in the menu.
    public var isEnabled: Bool
    /// Device keys (see `PointingDevice.key`) the user chose not to count.
    public var ignoredKeys: Set<String>

    public init(isEnabled: Bool, ignoredKeys: Set<String> = []) {
        self.isEnabled = isEnabled
        self.ignoredKeys = ignoredKeys
    }

    /// The result of `decide`.
    public struct Decision: Equatable, Sendable {
        /// What natural scrolling should be set to.
        public var naturalScrolling: Bool
        /// What to store as "the setting before a mouse appeared".
        /// nil means store nothing (clear it).
        public var rememberedBeforeMouse: Bool?
        /// The external mice that were counted, one per physical device.
        public var countedMice: [PointingDevice]
    }

    /// External mice that count: they pass the filter, are not on the ignore
    /// list, and appear once each even if the system reported them twice.
    public func countedMice(in devices: [PointingDevice]) -> [PointingDevice] {
        var seen = Set<String>()
        var result: [PointingDevice] = []
        for device in devices where device.isExternalMouse && !ignoredKeys.contains(device.key) {
            if seen.insert(device.identity).inserted {
                result.append(device)
            }
        }
        return result
    }

    /// Works out what natural scrolling should be, given the devices present
    /// now, the current setting, and what was remembered earlier.
    public func decide(
        presentDevices: [PointingDevice],
        current: Bool,
        rememberedBeforeMouse: Bool?
    ) -> Decision {
        let mice = countedMice(in: presentDevices)

        // Automatic switching is off: leave the setting alone and forget any
        // remembered value, so it cannot be restored later by surprise.
        guard isEnabled else {
            return Decision(naturalScrolling: current, rememberedBeforeMouse: nil, countedMice: mice)
        }

        if !mice.isEmpty {
            // A mouse is present. If nothing is remembered yet, this is the
            // moment the first mouse appeared, so remember the current value.
            let remembered = rememberedBeforeMouse ?? current
            return Decision(naturalScrolling: false, rememberedBeforeMouse: remembered, countedMice: mice)
        }

        // No mouse: restore what the user had before, then forget it.
        return Decision(naturalScrolling: rememberedBeforeMouse ?? true, rememberedBeforeMouse: nil, countedMice: mice)
    }
}
