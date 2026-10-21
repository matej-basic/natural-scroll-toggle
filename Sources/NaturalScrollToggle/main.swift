import AppKit
import Foundation
import ScrollCore

// Command line hooks, handy for testing without clicking the menu:
//   --status        prints "on" or "off"
//   --toggle        flips the setting and prints the new value
//   --set on|off    sets the value and prints it
//   --devices       lists the pointing devices the app sees, then exits
//   --backend       prints how the setting is applied (see ScrollPreference.swift)
let args = Array(CommandLine.arguments.dropFirst())

func label(_ on: Bool) -> String { on ? "on" : "off" }

/// Watches devices for 1.5 seconds, then prints one line per physical device.
func listDevices() {
    let monitor = MouseMonitor()
    monitor.start()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))

    let ignored = Settings.ignoredDeviceKeys
    for device in monitor.devices {
        let verdict: String
        if !device.isExternalMouse {
            verdict = "rejected"
        } else if ignored.contains(device.key) {
            verdict = "ignored"
        } else {
            verdict = "accepted"
        }
        let builtIn = device.builtIn.map { $0 ? "1" : "0" } ?? "nil"
        let pairs = device.usagePairs.map { "\($0.page)/\($0.usage)" }.joined(separator: ",")
        print("\(verdict)  \(device.key)  \(device.displayName)  transport=\(device.transport ?? "nil") builtIn=\(builtIn) pairs=[\(pairs)]")
    }
}

if let first = args.first {
    switch first {
    case "--status":
        print(label(NaturalScrolling.isEnabled))
    case "--toggle":
        print(label(NaturalScrolling.toggle()))
    case "--set":
        guard args.count > 1, ["on", "off"].contains(args[1]) else {
            FileHandle.standardError.write(Data("usage: --set on|off\n".utf8))
            exit(2)
        }
        NaturalScrolling.isEnabled = (args[1] == "on")
        print(label(NaturalScrolling.isEnabled))
    case "--devices":
        listDevices()
    case "--backend":
        print(NaturalScrolling.backend.rawValue)
    default:
        FileHandle.standardError.write(Data("unknown argument: \(first)\n".utf8))
        exit(2)
    }
    exit(0)
}

// Normal start: run as a menu bar app with no Dock icon.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
