// Tests use the swift-testing library (`import Testing`), not XCTest:
// the Command Line Tools on macOS ship swift-testing but not XCTest, and
// swift-testing is also part of the Linux Swift toolchain.
import Testing
@testable import ScrollCore

// Fixtures copied from what docs/RESEARCH.md section 2.3 saw on the
// development Mac, plus two devices that were not present there.
enum Fixture {
    /// Built-in trackpad: Built-In = 1, transport FIFO, touch pad pair, no IDs.
    static let builtInTrackpad = PointingDevice(
        identity: "obj-1",
        product: "Apple Internal Keyboard / Trackpad",
        transport: "FIFO",
        builtIn: true,
        usagePairs: [.init(page: 1, usage: 2), .init(page: 1, usage: 1), .init(page: 13, usage: 5), .init(page: 65280, usage: 12)]
    )

    /// Logitech Unifying receiver: USB, no Built-In property.
    static let unifyingReceiver = PointingDevice(
        identity: "0x14200000",
        vendorID: 0x046d,
        productID: 0xc53f,
        product: "USB Receiver",
        transport: "USB",
        builtIn: nil,
        usagePairs: [.init(page: 1, usage: 2), .init(page: 1, usage: 1), .init(page: 12, usage: 1), .init(page: 1, usage: 128), .init(page: 65468, usage: 136)]
    )

    /// Logitech Bolt receiver.
    static let boltReceiver = PointingDevice(
        identity: "0x14300000",
        vendorID: 0x046d,
        productID: 0xc547,
        product: "USB Receiver",
        transport: "USB",
        usagePairs: [.init(page: 1, usage: 2), .init(page: 1, usage: 1)]
    )

    /// A Logitech mouse paired over Bluetooth directly (not seen on this Mac).
    static let bluetoothMouse = PointingDevice(
        identity: "0x5a1b2c3d",
        vendorID: 0x046d,
        productID: 0xb034,
        product: "MX Master 3S",
        transport: "Bluetooth Low Energy",
        usagePairs: [.init(page: 1, usage: 2)]
    )

    /// Apple Magic Trackpad over Bluetooth: external, but a touch pad.
    static let magicTrackpad = PointingDevice(
        identity: "0x6e7f8091",
        vendorID: 0x05ac,
        productID: 0x0265,
        product: "Magic Trackpad",
        transport: "Bluetooth",
        usagePairs: [.init(page: 1, usage: 2), .init(page: 13, usage: 5)]
    )
}

@Suite("Device filter")
struct DeviceFilterTests {
    @Test func builtInTrackpadIsRejected() {
        #expect(!Fixture.builtInTrackpad.isExternalMouse)
        #expect(Fixture.builtInTrackpad.rejectionReason == "built-in")
    }

    @Test func logitechReceiverIsAccepted() {
        #expect(Fixture.unifyingReceiver.isExternalMouse)
        #expect(Fixture.boltReceiver.isExternalMouse)
    }

    @Test func bluetoothMouseIsAccepted() {
        #expect(Fixture.bluetoothMouse.isExternalMouse)
    }

    @Test func magicTrackpadIsRejected() {
        #expect(!Fixture.magicTrackpad.isExternalMouse)
        #expect(Fixture.magicTrackpad.rejectionReason == "trackpad")
    }

    @Test func unknownTransportIsRejected() {
        var device = Fixture.bluetoothMouse
        device.transport = "SPI"
        #expect(!device.isExternalMouse)
        device.transport = nil
        #expect(!device.isExternalMouse)
    }

    @Test func keyAndDisplayName() {
        #expect(Fixture.unifyingReceiver.key == "046d:c53f")
        #expect(Fixture.unifyingReceiver.displayName == "USB Receiver (046d:c53f)")
        #expect(Fixture.builtInTrackpad.key == "Apple Internal Keyboard / Trackpad")
        #expect(Fixture.builtInTrackpad.displayName == "Apple Internal Keyboard / Trackpad")
    }
}

@Suite("Auto-switch policy")
struct AutoSwitchPolicyTests {
    let enabled = AutoSwitchPolicy(isEnabled: true)

    @Test func ignoreListExcludesDevice() {
        let policy = AutoSwitchPolicy(isEnabled: true, ignoredKeys: ["046d:c53f"])
        let mice = policy.countedMice(in: [Fixture.unifyingReceiver, Fixture.boltReceiver, Fixture.builtInTrackpad])
        #expect(mice.map(\.key) == ["046d:c547"])

        // With only the ignored receiver present, it behaves as if no mouse is there.
        let decision = policy.decide(presentDevices: [Fixture.unifyingReceiver], current: false, rememberedBeforeMouse: true)
        #expect(decision.countedMice.isEmpty)
        #expect(decision.naturalScrolling == true)
        #expect(decision.rememberedBeforeMouse == nil)
    }

    @Test func mouseAppearsTurnsOffAndRemembers() {
        let decision = enabled.decide(
            presentDevices: [Fixture.builtInTrackpad, Fixture.unifyingReceiver],
            current: true,
            rememberedBeforeMouse: nil
        )
        #expect(decision.naturalScrolling == false)
        #expect(decision.rememberedBeforeMouse == true)
    }

    @Test func secondMouseKeepsFirstMemory() {
        // Natural scrolling is already off because of the first mouse; the
        // memory from before the first mouse must not be overwritten.
        let decision = enabled.decide(
            presentDevices: [Fixture.unifyingReceiver, Fixture.bluetoothMouse],
            current: false,
            rememberedBeforeMouse: true
        )
        #expect(decision.naturalScrolling == false)
        #expect(decision.rememberedBeforeMouse == true)
    }

    @Test func mouseDisappearsRestores() {
        let restoreOn = enabled.decide(presentDevices: [Fixture.builtInTrackpad], current: false, rememberedBeforeMouse: true)
        #expect(restoreOn.naturalScrolling == true)
        #expect(restoreOn.rememberedBeforeMouse == nil)

        let restoreOff = enabled.decide(presentDevices: [Fixture.builtInTrackpad], current: false, rememberedBeforeMouse: false)
        #expect(restoreOff.naturalScrolling == false)
        #expect(restoreOff.rememberedBeforeMouse == nil)
    }

    @Test func noMemoryDefaultsToOn() {
        let decision = enabled.decide(presentDevices: [], current: false, rememberedBeforeMouse: nil)
        #expect(decision.naturalScrolling == true)
        #expect(decision.rememberedBeforeMouse == nil)
    }

    @Test func autoDisabledChangesNothing() {
        let policy = AutoSwitchPolicy(isEnabled: false)
        for current in [true, false] {
            let withMouse = policy.decide(presentDevices: [Fixture.unifyingReceiver], current: current, rememberedBeforeMouse: nil)
            #expect(withMouse.naturalScrolling == current)
            #expect(withMouse.rememberedBeforeMouse == nil)

            let withoutMouse = policy.decide(presentDevices: [], current: current, rememberedBeforeMouse: !current)
            #expect(withoutMouse.naturalScrolling == current)
        }
    }

    @Test func duplicateObjectsCountOnce() {
        // The same receiver reported twice, as IOKit does for one physical device.
        var duplicate = Fixture.unifyingReceiver
        duplicate.usagePairs = [.init(page: 1, usage: 2)]
        let decision = enabled.decide(
            presentDevices: [Fixture.unifyingReceiver, duplicate, Fixture.builtInTrackpad],
            current: true,
            rememberedBeforeMouse: nil
        )
        #expect(decision.countedMice.count == 1)
        #expect(decision.naturalScrolling == false)
    }

    @Test func trackpadsAloneDoNotCount() {
        let decision = enabled.decide(
            presentDevices: [Fixture.builtInTrackpad, Fixture.magicTrackpad],
            current: true,
            rememberedBeforeMouse: nil
        )
        #expect(decision.countedMice.isEmpty)
        #expect(decision.naturalScrolling == true)
    }
}
