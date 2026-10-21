import Foundation

/// One HID usage pair, for example page 1 / usage 2 (Generic Desktop, Mouse)
/// or page 13 / usage 5 (Digitizer, Touch Pad).
public struct UsagePair: Hashable, Codable, Sendable {
    public var page: Int
    public var usage: Int

    public init(page: Int, usage: Int) {
        self.page = page
        self.usage = usage
    }

    /// Digitizer / Touch Pad. Trackpads report this pair, mice do not.
    public static let touchPad = UsagePair(page: 13, usage: 5)
}

/// A pointing device as the system reports it, reduced to the few
/// properties the app needs. The app fills this in from IOKit; tests fill it
/// in by hand.
public struct PointingDevice: Hashable, Codable, Sendable {
    /// Stable id for one physical device. One physical device can show up as
    /// several HID objects, and they all share this id.
    public var identity: String
    public var vendorID: Int?
    public var productID: Int?
    /// Product name, for example "USB Receiver".
    public var product: String?
    /// How it is connected, for example "USB", "Bluetooth", "FIFO".
    public var transport: String?
    /// The "Built-In" property. Missing on most external devices.
    public var builtIn: Bool?
    public var usagePairs: [UsagePair]

    public init(
        identity: String,
        vendorID: Int? = nil,
        productID: Int? = nil,
        product: String? = nil,
        transport: String? = nil,
        builtIn: Bool? = nil,
        usagePairs: [UsagePair] = []
    ) {
        self.identity = identity
        self.vendorID = vendorID
        self.productID = productID
        self.product = product
        self.transport = transport
        self.builtIn = builtIn
        self.usagePairs = usagePairs
    }

    /// Why the device does not count as an external mouse, or nil if it does.
    /// The checks follow docs/RESEARCH.md section 2.4:
    ///   1. not built in (the property is missing or false),
    ///   2. connected over USB or Bluetooth,
    ///   3. not a touch pad (no usage pair 13/5).
    public var rejectionReason: String? {
        if builtIn == true {
            return "built-in"
        }
        if usagePairs.contains(.touchPad) {
            return "trackpad"
        }
        let link = (transport ?? "").lowercased()
        if !(link.contains("usb") || link.contains("bluetooth")) {
            return "not USB or Bluetooth"
        }
        return nil
    }

    /// True when this device should count as an external mouse.
    public var isExternalMouse: Bool {
        rejectionReason == nil
    }

    /// "046d:c53f" when both IDs are known, otherwise the product name,
    /// otherwise the identity. This is what the ignore list stores.
    public var key: String {
        if let ids = idString {
            return ids
        }
        return product ?? identity
    }

    /// A label for the menu, such as "USB Receiver (046d:c53f)".
    public var displayName: String {
        let name = product ?? "Unknown device"
        if let ids = idString {
            return "\(name) (\(ids))"
        }
        return name
    }

    private var idString: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "%04x:%04x", vendorID, productID)
    }
}
