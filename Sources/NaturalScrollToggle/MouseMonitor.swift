import Foundation
import IOKit.hid
import ScrollCore

/// Watches for pointing devices (anything that reports itself as a mouse,
/// which includes trackpads and wireless receivers) being connected and
/// disconnected.
///
/// It only asks the system to be told when devices come and go, and reads
/// their descriptive properties. It never opens a device or reads its input,
/// so macOS does not ask for the Input Monitoring permission.
/// See docs/RESEARCH.md section 2.2.
final class MouseMonitor {
    /// Called on the main thread, about 300 ms after the last change, with
    /// one entry per physical device.
    var onChange: (([PointingDevice]) -> Void)?

    /// The devices present right now, one per physical device.
    var devices: [PointingDevice] {
        devicesByIdentity.values.sorted { $0.identity < $1.identity }
    }

    private let manager: IOHIDManager
    /// One entry per physical device.
    private var devicesByIdentity: [String: PointingDevice] = [:]
    /// How many HID objects each physical device currently has. A device is
    /// only removed when its last object goes away.
    private var objectCount: [String: Int] = [:]
    /// Which physical device each HID object belongs to, so removal works
    /// even if the object's properties can no longer be read.
    private var identityOfObject: [UnsafeMutableRawPointer: String] = [:]
    private var pendingNotification: DispatchWorkItem?

    init() {
        // kIOHIDOptionsTypeNone: no special options.
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Starts watching. Devices already connected are reported through the
    /// same callback as new ones, shortly after the run loop starts.
    func start() {
        // Only devices that list Generic Desktop (page 1) / Mouse (usage 2).
        let matching: [String: Int] = [
            kIOHIDDeviceUsagePageKey: 1,
            kIOHIDDeviceUsageKey: 2,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        // C callbacks cannot capture `self`, so it is passed as a raw pointer.
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<MouseMonitor>.fromOpaque(context).takeUnretainedValue().deviceAdded(device)
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else { return }
                Unmanaged<MouseMonitor>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
            }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // IOHIDManagerOpen is deliberately NOT called. Opening is what needs
        // the Input Monitoring permission, and it is not needed to see devices.

        // Report once even if no device matches at all.
        scheduleNotification()
    }

    // MARK: Callbacks (run on the main thread)

    private func deviceAdded(_ device: IOHIDDevice) {
        let pointer = Unmanaged.passUnretained(device).toOpaque()
        guard identityOfObject[pointer] == nil else { return }

        let info = Self.describe(device)
        identityOfObject[pointer] = info.identity
        objectCount[info.identity, default: 0] += 1
        if devicesByIdentity[info.identity] == nil {
            devicesByIdentity[info.identity] = info
        }
        scheduleNotification()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let pointer = Unmanaged.passUnretained(device).toOpaque()
        guard let identity = identityOfObject.removeValue(forKey: pointer) else { return }

        let remaining = (objectCount[identity] ?? 1) - 1
        if remaining > 0 {
            objectCount[identity] = remaining
        } else {
            objectCount[identity] = nil
            devicesByIdentity[identity] = nil
        }
        scheduleNotification()
    }

    /// Waits until devices have stopped changing for 300 ms, then reports.
    /// A receiver or hub often announces several objects in a quick burst.
    private func scheduleNotification() {
        pendingNotification?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onChange?(self.devices)
        }
        pendingNotification = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Reading device properties

    /// Builds a PointingDevice from the properties of one HID object.
    static func describe(_ device: IOHIDDevice) -> PointingDevice {
        func property(_ key: String) -> CFTypeRef? {
            IOHIDDeviceGetProperty(device, key as CFString)
        }
        func number(_ key: String) -> Int? {
            (property(key) as? NSNumber)?.intValue
        }

        // LocationID is shared by all objects of one physical device. Devices
        // without it get an id unique to this object.
        let identity: String
        if let location = number(kIOHIDLocationIDKey) {
            identity = String(format: "location-0x%08x", location)
        } else {
            identity = "object-\(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))"
        }

        var pairs: [UsagePair] = []
        if let list = property(kIOHIDDeviceUsagePairsKey) as? [[String: Any]] {
            for entry in list {
                if let page = (entry[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue,
                    let usage = (entry[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue
                {
                    pairs.append(UsagePair(page: page, usage: usage))
                }
            }
        }

        return PointingDevice(
            identity: identity,
            vendorID: number(kIOHIDVendorIDKey),
            productID: number(kIOHIDProductIDKey),
            product: property(kIOHIDProductKey) as? String,
            transport: property(kIOHIDTransportKey) as? String,
            builtIn: (property(kIOHIDBuiltInKey) as? NSNumber)?.boolValue,
            usagePairs: pairs
        )
    }
}
