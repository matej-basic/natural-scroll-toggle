# Research: natural scrolling toggle with external mouse detection

Date: 2026-10-21. Target machine: Apple silicon MacBook Pro, macOS 27.0.1, Swift 6.4 via Command Line Tools only (SDK `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`).

Each claim is tagged. "Verified here" means I ran it on this machine and the output is quoted. "Read online" means it comes from the linked source and I did not reproduce it. "Not verified" means exactly that.

Scratch files for every probe live in `<scratch directory outside the project>/` (`hid-probe/`, `bundle-test/`, `gh/`). No application code was written in the project, nothing was committed, and no system setting was changed. In particular I did not call the scroll setter, so the live effect of the toggle is not verified on this machine (see section 1).

## 1. Toggling natural scrolling so it applies immediately

### 1.1 The preference key

Verified here:

```
$ defaults read -g com.apple.swipescrolldirection
0                                   (exit 0)
$ defaults read -g | grep -i -E "scroll|swipe"
    "com.apple.swipescrolldirection" = 0;
```

So natural scrolling is currently OFF (0 = off, 1 = on). The same value read through APIs, from a swiftc binary:

```
UserDefaults.standard.bool(forKey: "com.apple.swipescrolldirection") = false
CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication)          = Optional(0)
swipeScrollDirection()   (private getter, see below)                  = false
```

When the key is absent, the private getter returns true (the disassembly has a `cbz` on a missing value that loads 1), so the system default is natural scrolling ON. Verified here by disassembly of `swipeScrollDirection` in lldb.

Read online: this one value drives both the trackpad and the mouse checkbox, which is why per-device behavior needs a separate mechanism (https://github.com/dongzhenye/reverse-scroll-cli/blob/HEAD/docs/research.md).

### 1.2 Writing the key alone does not apply live

Read online, from three independent sources:

- ScrollSwitcher write-up (2021): `defaults write -g com.apple.swipescrolldirection -bool YES` does not change the running behavior, and the Mouse pane only reflects it after being reopened in a new session. https://shadowfacts.net/2021/scrollswitcher/
- NaturalOnBattery source comment: writing the plist key alone updates the pref, but the HID event system keeps its old direction until told, so it calls the private `setSwipeScrollDirection()`. The fallback (key write plus notification) "takes effect after logout". https://github.com/jackharvest/NaturalOnBattery/blob/HEAD/main.swift
- ScrollSwitch README says the same. https://github.com/abhip1008/scrollswitch

Not verified here: I did not run `defaults write` because it would change the user's real preference outside the allowed directories. The sources agree, and the mechanism below explains why.

### 1.3 What works: the private function `setSwipeScrollDirection(Bool)`

System Settings applies the change by calling `setSwipeScrollDirection` in `/System/Library/PrivateFrameworks/PreferencePanesSupport.framework`. The ScrollSwitcher author found it by disassembling the Mouse pane (`-[MouseController scrollingBehavior:]` calls it) and reports the signature as a plain bool parameter (https://shadowfacts.net/2021/scrollswitcher/). At least five small projects call it the same way:

- BrChung dotfiles script, uses `@_silgen_name` plus a distributed notification: https://github.com/BrChung/.dotfiles/blob/HEAD/scripts/set_scroll_direction.swift
- NaturalOnBattery, uses `dlopen`/`dlsym`, with a fallback: https://github.com/jackharvest/NaturalOnBattery/blob/HEAD/main.swift
- scroll-swap: https://github.com/leongmichael/scroll-swap/blob/HEAD/Sources/ScrollSwap/ScrollDirectionController.swift
- ScrollSwitch (created 2026-10-09, single author, 0 stars, so weak evidence by itself): https://github.com/abhip1008/scrollswitch
- The ScrollSwitcher app itself (2021).

Verified here on macOS 27.0.1, `dlopen` plus `dlsym` from a swiftc binary:

```
.../PreferencePanesSupport  dlopen ok
  setSwipeScrollDirection   FOUND
  swipeScrollDirection      FOUND   (getter; called, returned false, matches the pref)
  _setSwipeScrollDirection  nil
  getSwipeScrollDirection   nil
```

Verified here by disassembly (lldb, `disassemble -n setSwipeScrollDirection`, arm64e): the function takes its argument in x0 (`cmp x19, #1; cset w1, eq`), selects `kCFBooleanTrue` or `kCFBooleanFalse`, references the string `com.apple.swipescrolldirection`, builds a block named `__setSwipeScrollDirection_block_invoke`, and further down references `SwipeScrollDirectionDidChangeNotification` followed by a call that looks like a distributed-notification post. My reading is that the function writes the preference, pushes the value to the system, and posts the change notification itself. That reading is an inference from disassembly, not something I observed at runtime.

The string `SwipeScrollDirectionDidChangeNotification` also still exists in macOS 27 system binaries (Read online: the ipsw-diffs listing for macOS 27.0 lists it under `RingLightHelper`, https://github.com/blacktop/ipsw-diffs, path `macOS/27_0_26A428_vs_27_2_26B5086k_Mac18,5/MACHOS/filesystem/System/Library/CoreServices/ControlCenter.app/Contents/XPCServices/RingLightHelper.xpc/Contents/MacOS/RingLightHelper.md`).

Not verified here: calling the setter and seeing scrolling invert, and System Settings redrawing its checkbox. I deliberately did not call it. The first implementation task should do a flip, check `defaults read -g com.apple.swipescrolldirection`, scroll with a wheel, and flip back.

### 1.4 The distributed notification

Name: `SwipeScrollDirectionDidChangeNotification`, posted on the distributed center. Per the ScrollSwitcher write-up, the Mouse pane observes it to update its checkbox, and it is not what changes the input behavior (https://shadowfacts.net/2021/scrollswitcher/). Since the disassembly suggests the setter already posts it, an extra post is probably redundant, but every small project posts it anyway and it costs nothing.

Exact call sequence from the BrChung script (Read online), in Swift:

```swift
@_silgen_name("setSwipeScrollDirection")
func setSwipeScrollDirection(_ direction: Bool)

setSwipeScrollDirection(natural)

CFNotificationCenterPostNotification(
    CFNotificationCenterGetDistributedCenter(),
    CFNotificationName("SwipeScrollDirectionDidChangeNotification" as CFString),
    nil, nil, true)
```

`@_silgen_name` needs the symbol at link time, which means linking the private framework (the ScrollSwitcher author linked `/System/Library/PrivateFrameworks/PreferencePanesSupport.framework`). With Command Line Tools only, `dlopen`/`dlsym` is simpler and also degrades gracefully. NaturalOnBattery's version (Read online):

```swift
typealias SetFn = @convention(c) (Bool) -> Void
let h = dlopen("/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport", RTLD_LAZY)
let f = unsafeBitCast(dlsym(h, "setSwipeScrollDirection"), to: SetFn.self)
f(natural)
```

I confirmed the dlopen/dlsym lookup and the `@convention(c) () -> Bool` getter cast work from a swiftc-built binary on macOS 27.0.1 (`get.swift`: output above). The setter cast is the same pattern but was not executed.

### 1.5 Older alternative: `CGSSetSwipeScrollDirection`

DynamicScrollDirection (2017) and an invainn dotfiles script call `CGSSetSwipeScrollDirection(_CGSDefaultConnection(), natural)`, then `CFPreferencesSetAppValue(key, natural, kCFPreferencesAnyApplication)` plus `CFPreferencesAppSynchronize`, then post the notification.

- https://github.com/snosrap/DynamicScrollDirection/blob/HEAD/DynamicScrollDirection/main.m
- https://github.com/invainn/dotfiles/blob/HEAD/scroll-switcher/.local/bin/set-scroll-direction.swift

Verified here that both `CGSSetSwipeScrollDirection` and `_CGSDefaultConnection` still resolve via `dlsym` in SkyLight, CoreGraphics and ApplicationServices on macOS 27.0.1. Not verified that the call still changes behavior. Use it only as a fallback.

### 1.6 Pitfalls found in the sources

- Do not use `UserDefaults.standard.set(_, forKey:)` for this key: that writes the app's own domain, not the global one (scroll-swap does this, so its pref write is a no-op).
- `UserDefaults(suiteName: "NSGlobalDomain")` is logged as invalid, and `setPersistentDomain` on the global domain reset unrelated global settings. The ScrollSwitcher author warns against both. https://shadowfacts.net/2021/scrollswitcher/
- If a pref write is needed, use CF: `CFPreferencesSetValue(key, bool, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)` followed by `CFPreferencesSynchronize` with the same three arguments (this is what NaturalOnBattery's fallback does).
- App Sandbox must be off, since writing the global domain fails inside it (ScrollSwitcher write-up, ScrollSwitch README). A bare swiftc app is unsandboxed, so this is automatic here. Mac App Store distribution is out.
- Sequoia 15 / Tahoe 26: I found no report that the private function was removed or broke. The only macOS 26/27 evidence is the symbol existing on this machine and the notification string present in macOS 27 binaries. No source I found tests the setter on 26 or 27 specifically, so treat "works on 27" as not verified until the first flip is tried.

### 1.7 Event tap alternative

Scroll Reverser installs a `CGEventTap` on scroll events and negates the line, point, fixed-point and IOHID deltas, and separates mouse from trackpad with heuristics (the `continuous` flag, recent touch tracking). The active tap needs Accessibility permission. Sources: https://github.com/pilotmoon/Scroll-Reverser and the analysis in https://github.com/dongzhenye/reverse-scroll-cli/blob/HEAD/docs/research.md. Mos (https://github.com/Caldis/Mos) and LinearMouse (https://github.com/linearmouse/linearmouse) also work at the event level; I only read their descriptions, not their code.

Pros: public API (CGEventTap), per-device behavior, does not touch the system preference. Cons: Accessibility prompt, heuristics to tell mouse from trackpad (Magic Mouse and smooth wheels report as continuous), the tap can be disabled by the system and must be re-enabled, more code. The system-preference route is a few lines and needs no permission, at the cost of a private symbol. Preferred route stays as the brief says.

## 2. Detecting an external mouse

### 2.1 API availability (verified here)

`import IOKit.hid` compiles with plain `swiftc` and the Command Line Tools SDK. These all resolved: `IOHIDManagerCreate`, `IOHIDManagerSetDeviceMatching`, `IOHIDManagerRegisterDeviceMatchingCallback`, `IOHIDManagerRegisterDeviceRemovalCallback`, `IOHIDManagerScheduleWithRunLoop`, `IOHIDManagerCopyDevices`, `IOHIDDeviceGetProperty`, `IOHIDCheckAccess`. The header constants exist (SDK `IOHIDDeviceKeys.h`/`IOHIDKeys.h`): `kIOHIDTransportKey = "Transport"`, `kIOHIDBuiltInKey = "Built-In"`, `kIOHIDDeviceUsagePairsKey = "DeviceUsagePairs"`, `kIOHIDPrimaryUsagePageKey = "PrimaryUsagePage"`. Header transport value strings: "USB", "Bluetooth", "BluetoothLowEnergy" (no spaces), "SPI", "I2C", "AID", "SPU", "FIFO", "Virtual", others.

### 2.2 Permissions: matching callbacks without `IOHIDManagerOpen`

Verified here, three probes, all compiled with swiftc:

1. `hid-probe/probe.swift`: manager with a NULL matching dictionary, run loop scheduled, matching callback registered, no `IOHIDManagerOpen`. Result: 24 callbacks and `IOHIDManagerCopyDevices` count 24, all properties readable (name, transport, vendor, product, usage pairs, Built-In). No error, exit 0.
2. `hid-probe/open.swift`: same manager restricted to usage page 1 / usage 2, then calling `IOHIDManagerOpen`:

```
matching callbacks BEFORE open (usage 1/2 only): 3
IOHIDManagerOpen -> 0xe00002e2 kIOReturnNotPermitted
IOHIDCheckAccess(ListenEvent) = 1 (0=granted,1=denied,2=unknown)
```

So in this process context Input Monitoring is not granted, `Open` is refused, and matching callbacks plus property reads still work. That is direct evidence that callbacks do not need Input Monitoring.

3. `bundle-test/` app, ad-hoc signed bundle with a fresh bundle id (`test.claude.nstprobe`) launched with `open -W`, so it had its own TCC identity:

```
IOHIDCheckAccess(ListenEvent) before: 2          (2 = never decided)
mouse-usage matching callbacks (no Open): 3
IOHIDCheckAccess(ListenEvent) after enumeration: 2
```

State stayed "unknown" and the unified log held no `ListenEvent` TCC entry for the app (`log show --predicate 'subsystem == "com.apple.TCC"'`, only a `bundleRecordWithBundleIdentifier failed` lookup line, which is normal for an unregistered bundle id). Caveat: I cannot see the screen, so I cannot prove no dialog flashed. The unchanged "unknown" state plus the empty log make it unlikely.

Read online, conflicting reports: two Apple Developer Forums posts say `IOHIDManagerCopyDevices` triggered the Input Monitoring prompt or crashed (macOS 10.15 and a 2023 post), both with no replies and no code showing whether the manager was opened (https://developer.apple.com/forums/thread/124368, https://developer.apple.com/forums/thread/735999). SDL's approach is to detect denial only by attempting an open, which implies enumeration itself is not gated (https://git.axiodl.com/encounter/SDL/commit/172865ff137532123ec06177119be163ba1811f5). Apple's header says `IOHIDManagerOpen` opens current and future devices (SDK `IOHIDManager.h`), which is the call that does the gated work. ScrollSwitch's author makes the same claim from the IOService side: their monitor "never opens" devices and so needs no Input Monitoring (https://github.com/abhip1008/scrollswitch).

Conclusion: register callbacks and schedule on the main run loop, never call `IOHIDManagerOpen`, never read input values. Expected permission prompts: none. No entitlement or sandbox exception is involved because the app is unsandboxed. Not verified: behavior on a freshly installed Mac that has never seen the app with the dialog UI observed.

Removal callbacks: registered and scheduled in the probe, but I did not unplug anything, so removal firing is not verified here. DynamicScrollDirection registers the same pair without opening and relies on removal callbacks (https://github.com/snosrap/DynamicScrollDirection/blob/HEAD/DynamicScrollDirection/main.m, 2017).

### 2.3 What is on this machine right now (verified here)

Full output of `hid-probe/probe` (NULL matching, no Open). Columns: PrimaryUsagePage, PrimaryUsage (decimal), Transport, VendorID, ProductID, Product, Built-In, DeviceUsagePairs (page/usage decimal).

```
up=65280 u=255 transport=SPU vid=? pid=? name=wakehint builtIn=1 pairs=[65280/255]
up=1 u=2 transport=USB vid=0x046d pid=0xc53f name=USB Receiver builtIn=nil pairs=[1/2,1/1,12/1,1/128,65468/136]
up=65292 u=1 transport=SPU vid=? pid=? name=cma builtIn=1 pairs=[65292/1]
up=1 u=2 transport=FIFO vid=? pid=? name=Apple Internal Keyboard / Trackpad builtIn=1 pairs=[1/2,1/1,13/5,65280/12]
up=65280 u=9 transport=SPU vid=0x05ac pid=0x8104 name=gyro builtIn=1 pairs=[65280/9]
up=1 u=2 transport=USB vid=0x046d pid=0xc547 name=USB Receiver builtIn=nil pairs=[1/2,1/1]
up=65292 u=5 transport=SPU vid=? pid=? name=devmotion6 builtIn=1 pairs=[65292/5]
up=12 u=1 transport=Audio vid=? pid=? name=Headset builtIn=1 pairs=[12/1]
up=65280 u=15 transport=USB vid=0x05ac pid=0x0000 name=Keyboard Backlight builtIn=1 pairs=[65280/15]
up=65280 u=11 transport=FIFO vid=? pid=? name=Apple Internal Keyboard / Trackpad builtIn=1 pairs=[65280/11]
up=65280 u=1 transport=USB vid=0x046d pid=0xc547 name=USB Receiver builtIn=nil pairs=[65280/1,65280/2]
up=1 u=6 transport=FIFO vid=? pid=? name=Apple Internal Keyboard / Trackpad builtIn=1 pairs=[1/6,12/1,65280/6]
up=12 u=1 transport=USB vid=0x1532 pid=0x0555 name=Razer BlackShark V2 Pro 2.4 builtIn=nil pairs=[12/1,65280/1]
up=65280 u=3 transport=FIFO vid=? pid=? name=Apple Internal Keyboard / Trackpad builtIn=1 pairs=[65280/3]
up=65280 u=13 transport=FIFO vid=? pid=? name=Apple Internal Keyboard / Trackpad builtIn=1 pairs=[65280/13]
up=65280 u=72 transport=SPMI vid=? pid=? name=BTM builtIn=nil pairs=[65280/72]
up=65280 u=1 transport=USB vid=0x046d pid=0xc53f name=USB Receiver builtIn=nil pairs=[65280/1,65280/2,65280/4]
up=65280 u=95 transport=FIFO vid=? pid=? name=Apple Internal Keyboard / Trackpad builtIn=1 pairs=[65280/95]
up=65280 u=3 transport=SPU vid=0x05ac pid=0x8104 name=accel builtIn=1 pairs=[65280/3]
up=1 u=6 transport=USB vid=0x046d pid=0xc53f name=USB Receiver builtIn=nil pairs=[1/6]
up=65280 u=4 transport=SPU vid=? pid=? name=als builtIn=1 pairs=[65280/4]
up=1 u=6 transport=USB vid=0x046d pid=0xc547 name=USB Receiver builtIn=nil pairs=[1/6,12/1,1/128]
up=65280 u=5 transport=SPU vid=0x05ac pid=0x8104 name=als-temp builtIn=1 pairs=[65280/5]
up=32 u=138 transport=SPU vid=? pid=? name=las builtIn=1 pairs=[32/138]
total callbacks: 24
CopyDevices count: 24
```

Usage page key: 65280 = 0xFF00 (vendor page), 12 = Consumer, 13 = Digitizer, 32 = Sensor, 1 = Generic Desktop (2 = Mouse, 6 = Keyboard).

Reading it:

- The built-in trackpad is the device named "Apple Internal Keyboard / Trackpad": PrimaryUsage 1/2 (mouse), pairs include 13/5 (Digitizer, Touch Pad), transport FIFO, Built-In = 1, and it has no VendorID or ProductID property at all. A filter that requires a vendor ID would drop it by accident, but one that tests vendor 0x05ac to exclude Apple devices would not see it.
- Two Logitech USB receivers (046d:c53f and 046d:c547, both called "USB Receiver") each expose a 1/2 mouse interface, a keyboard interface, and vendor interfaces. They are matched as mice. This is a real hazard: a receiver stays plugged in whether the wireless mouse is on, asleep or in a bag, so receiver presence does not equal mouse presence. Nothing in the HID properties distinguishes the two.
- Matching on usage page 1 / usage 2 returned exactly 3 devices: the two receivers and the built-in trackpad (`open.swift`, `bundle-test`).
- One physical device shows up as several IOHIDDevice objects (the receivers and the internal keyboard/trackpad each appear 4 to 5 times), so count unique devices, not callbacks.

Other commands, verified here:

- `system_profiler SPUSBDataType` printed nothing and exited 0 on this macOS version. `system_profiler SPUSBHostDataType` works and lists, behind a CalDigit TS5 Plus hub: two Logitech "USB Receiver" devices (046d:c547 and 046d:c53f, manufacturer Logitech), a C270 HD webcam, and a Razer BlackShark V2 Pro 2.4 headset (1532:0555).
- `system_profiler SPBluetoothDataType`: controller on, no connected devices. Not Connected: a Mac mini, OnePlus Buds Z2. No Bluetooth mouse or trackpad is paired.
- `ioreg -p IOUSB -l -w0 | grep -i -E "mouse|product"` is unusable as given (it matches a huge IOKitDiagnostics line and prints about 89 KB). Filtering on `USB Product Name` and `USB Vendor Name` shows the same Logitech "USB Receiver" entries and the Razer headset.
- `ioreg -r -c AppleMultitouchDevice` shows an `AppleMultitouchDevice` (the built-in trackpad), with `SupportsGestureScrolling = Yes`.

Net: right now the only candidate external pointer is "a Logitech wireless mouse via a USB receiver", and no Bluetooth pointing device is present. I could not observe a Bluetooth mouse or an Apple Magic Trackpad on this machine.

### 2.4 Distinguishing the built-in trackpad and Magic Trackpad from a mouse

Evidence for each signal:

- Built-In = 1: set on the built-in trackpad here (verified). Absent (nil) on USB devices here, so treat absent as not built-in. ScrollSwitch notes the key is missing on some devices and falls back to transport SPI/FIFO (Read online, https://github.com/abhip1008/scrollswitch).
- Transport: built-in devices here report FIFO and SPU (verified). Header lists SPI, I2C, AID, Virtual as well. External mice report USB or Bluetooth.
- Usage pair 13/5 (Digitizer, Touch Pad): present on the built-in trackpad here (verified). Read online: IORegistry dumps of a Magic Trackpad show pairs 1/2, 1/1 and 13/5 (khronokernel/DarwinDumped, `MacPro/MacPro6,1/IORegistry/IOregViewer/Resources/dataFiles/IOService/data1371.txt`, product "Aleams Magic Trackpad"). Other dumps of "Magic Trackpad 2" list vendor-page interfaces, so only the interface with primary usage 1/2 matters.
- Vendor and product IDs for Apple external devices (Read online, Linux `hid-ids.h`, https://github.com/torvalds/linux/blob/master/drivers/hid/hid-ids.h): USB vendor 0x05ac, Bluetooth vendor 0x004c. Magic Mouse 0x030d, Magic Mouse 2 0x0269, Magic Mouse 2 USB-C 0x0323, Magic Trackpad 0x030e, Magic Trackpad 2 0x0265, USB-C 0x0324.

Proposed filter, applied to each IOHIDDevice from a manager that matches usage page 0x01 / usage 0x02:

```
accept if ALL of:
  1. Built-In property is absent or 0
  2. Transport string, lowercased, contains "usb" or "bluetooth"
     (covers "USB", "Bluetooth", "BluetoothLowEnergy"; rejects FIFO, SPI, SPU, I2C, AID, Virtual)
  3. No entry in DeviceUsagePairs has DeviceUsagePage == 13 and DeviceUsage == 5
     (touch pad: rejects Magic Trackpad and third-party touchpads)
identify a physical device by LocationID if present, else by the IOHIDDevice pointer;
external mouse present  <=>  the set of accepted identities is non-empty
```

Notes and open choices:

- Magic Mouse passes this filter. I expect it reports 1/2 without 13/5 but I could not verify that here. If the user wants the Magic Mouse to keep natural scrolling, add a name or product-ID exclusion (0x030d, 0x0269, 0x0323). Flag this as a user decision.
- Receivers (like the two Logitech ones here) are always present. With this filter the app will never see the mouse "disconnect" while its receiver stays plugged in. Options: accept this, or add a "ignore these vendor/product IDs" list, or offer a manual override in the menu.
- Count unique devices in an app-owned set keyed on identity, adding in the matching callback and removing in the removal callback. Do not derive the count from `IOHIDManagerCopyDevices` inside the removal callback (DynamicScrollDirection does this and subtracts one if the device is still in the set).
- Existing devices arrive through the matching callback right after the run loop starts (verified: all 24 arrived within a 2 second run), so no separate initial scan is needed.
- DynamicScrollDirection restricts matching to Transport = USB, which would exclude Bluetooth mice. The proposal above does not.

### 2.5 Alternatives if HID matching misbehaves

- `IOServiceAddMatchingNotification` with `IOServiceMatching("IOHIDDevice")` on `kIOMatchedNotification` and `kIOTerminatedNotification`, then reading properties with `IORegistryEntryCreateCFProperty`. ScrollSwitch does exactly this and says it never opens devices. Full source: https://github.com/abhip1008/scrollswitch (`Sources/ScrollSwitchCore/Monitors/DeviceMonitor.swift`). Notification iterators must be drained to arm them. This is the best fallback; it has the same permission profile.
- `NSWorkspace` notifications cover app launch and mount events, not HID. Not useful.
- Polling `ioreg -r -c IOHIDDevice` on a timer works but is slower and spawns a process each time. Last resort.
- CoreHID (Swift) is the modern Apple API; I did not evaluate it. An Apple DTS reply in the 2023 forum thread mentions it, but the page I fetched had no replies, so I cannot cite that.

## 3. Packaging without Xcode

All verified here with `bundle-test/` (a throwaway AppKit program with an `NSStatusItem` and the HID manager), built with `swiftc -O main.swift -o NSTProbe`.

- `NSApplication`/`NSStatusItem` work from a plain swiftc binary. Direct exec of the bare binary: `NSApplication.shared`, `setActivationPolicy(.accessory)` returned true, the status item was created with a non-nil button and `isVisible == true`. Launched as a bundle through `open`: same, except `setActivationPolicy(.accessory)` returned false because `LSUIElement` had already made the app accessory (policy value stayed 1). Do not treat `false` there as an error.
- Signing: swiftc on Apple Silicon links with an automatic ad-hoc signature already: `codesign -dv` printed `flags=0x20002(adhoc,linker-signed)`, `Signature=adhoc`, `Info.plist=not bound`. A copy with the signature removed (`codesign --remove-signature`) died immediately with exit 137 (SIGKILL). So a signature is required, but swiftc supplies one. For a bundle, run `codesign --force --sign - NST.app` after assembling so the Info.plist and resources are sealed; `codesign --verify --verbose=2` then answers "valid on disk" and "satisfies its Designated Requirement".
- Minimal layout that worked:

```
NST.app/Contents/MacOS/NSTProbe          (the swiftc binary)
NST.app/Contents/Info.plist
```

Info.plist keys used: `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, `CFBundlePackageType` (APPL), `CFBundleVersion`, `CFBundleShortVersionString`, `LSUIElement` = true, `LSMinimumSystemVersion`. `plutil -lint` reported OK. ScrollSwitch's Info.plist has the same set plus `NSSupportsAutomaticTermination` and `NSSupportsSuddenTermination` set to false, which is sensible for a menu bar tool that must stay alive (https://github.com/abhip1008/scrollswitch, `Resources/Info.plist`).
- `open` versus direct exec. `Bundle.main.bundleIdentifier` is nil for a bare binary and set for the bundle. Permission identity follows this: `IOHIDCheckAccess(ListenEvent)` returned 1 (denied) when I ran the binary directly, because the permission was attributed to the parent process I ran it from, and 2 (undecided) when launched with `open`, because the bundle got its own identity. Practical rule: always launch the bundle (`open` or Finder or login item), so any prompt names the app and any grant sticks to the app. Since the design never calls `IOHIDManagerOpen`, no prompt is expected either way.
- Whether `swift build` with a `Package.swift` also works under Command Line Tools only: not tested here. ScrollSwitch's Makefile does it and then copies the binary into a hand-built bundle and signs ad hoc (https://github.com/abhip1008/scrollswitch, `Makefile`), which is the same flow as above.
- Gatekeeper: a bundle built locally has no quarantine attribute, so it launches without a prompt. Not tested on a copy transferred from another machine.

## 4. Launch at login

Use `SMAppService.mainApp.register()` (macOS 13 and later, `import ServiceManagement`), called from the running app inside its `.app` bundle, with `unregister()` and `status` for the menu checkmark. It needs a real bundle with a bundle identifier, which section 3's layout provides. ScrollSwitch does this with an ad-hoc signed bundle and reports it works for personal use (https://github.com/abhip1008/scrollswitch, `Sources/ScrollSwitchCore/Support/LaunchAtLogin.swift` and README), but I did not call `register()` here, because it would add a login item to this user's account, so registration under ad-hoc signing is not verified. What I did verify: on an unregistered bundle `SMAppService.mainApp.status` returns 3 (`.notFound`), both from the bare binary and from the bundle in the scratchpad. ScrollSwitch's comment reads that as "not an installed bundle", but Apple developer forum replies describe `.notFound` as "the system has never seen this service", which is the normal state before the first `register()`, so I would not treat it as an error. The first implementation step should install the bundle in `~/Applications` or `/Applications`, call `register()`, and check that `status` becomes `.enabled` or `.requiresApproval` (the latter means the user has to flip the switch in System Settings, Login Items; `SMAppService.openSystemSettingsLoginItems()` opens that pane). If registration fails under ad-hoc signing, the fallback is a LaunchAgent at `~/Library/LaunchAgents/<bundle-id>.plist` with `Label`, `ProgramArguments` (the binary inside the bundle), and `RunAtLoad` true, loaded with `launchctl bootstrap gui/$(id -u) <plist>` (RunAtLoad and KeepAlive are documented in `man launchd.plist`, which I confirmed exists on this machine; the exact `bootstrap` form is standard launchctl usage and I did not run it).

## Recommended design

### Toggle

1. Read state: `CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)` as a Bool; if nil, treat as true (natural is the system default). Verified to return 0 here. The private getter `swipeScrollDirection()` gives the same answer.
2. Resolve once at startup: `dlopen("/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport", RTLD_LAZY)` then `dlsym(h, "setSwipeScrollDirection")` cast to `@convention(c) (Bool) -> Void`. If either step fails, show a warning state in the menu and fall back to step 5.
3. Apply: `setSwipeScrollDirection(natural)`.
4. Post `SwipeScrollDirectionDidChangeNotification` on the distributed center: `CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(), CFNotificationName("SwipeScrollDirectionDidChangeNotification" as CFString), nil, nil, true)`. Probably redundant (the setter appears to post it) and harmless.
5. Fallback chain if the symbol is missing: `CGSSetSwipeScrollDirection(_CGSDefaultConnection(), natural)` via `dlsym` on SkyLight; then `CFPreferencesSetValue` with `kCFPreferencesAnyApplication`, `kCFPreferencesCurrentUser`, `kCFPreferencesAnyHost`, `CFPreferencesSynchronize` with the same arguments, and the notification. Per the sources the last step alone takes effect at next login only.
6. Re-read the preference after the call and log a mismatch.
7. Observe `SwipeScrollDirectionDidChangeNotification` with `DistributedNotificationCenter.default()` to refresh the menu when something else (System Settings, another tool) changes the setting.
8. Never write the key through `UserDefaults.standard`, `UserDefaults(suiteName: NSGlobalDomain)` or `setPersistentDomain`.

### Detection

- One `IOHIDManager` with `kIOHIDOptionsTypeNone`, matching dictionary `{DeviceUsagePage: 1, DeviceUsage: 2}` (Generic Desktop, Mouse), matching and removal callbacks, `IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)`. No `IOHIDManagerOpen`.
- Per device apply the filter from section 2.4: Built-In absent or 0, Transport contains "usb" or "bluetooth" (case-insensitive), no usage pair 13/5. Keep a set of accepted unique device identities, updated in both callbacks.
- On change: set non-empty means natural OFF, empty means natural ON (or "restore the value the user had before the first mouse appeared", which I recommend remembering rather than forcing ON; this is a product decision). Debounce the transition by a few hundred ms, since a receiver or hub can re-enumerate several interfaces in a burst.
- Provide a manual toggle and an "Auto" check in the menu, plus an ignore list by vendor/product ID for always-present receivers and for the Magic Mouse question.
- Fallback if HID callbacks prove unreliable: `IOServiceAddMatchingNotification` on `IOHIDDevice` as in ScrollSwitch.

### Permissions to expect

- Accessibility: none (no event tap).
- Input Monitoring: none, as long as `IOHIDManagerOpen` is never called. Verified here that matching and property reads work while `Open` returns `kIOReturnNotPermitted`, and that a fresh bundle id stays "undecided" after enumeration. Residual risk: older forum reports (unresolved) of a prompt on enumeration; a first-run check on a clean user account would close it.
- App Sandbox: off (the swiftc build is unsandboxed by default).
- Login Items: possible one-time approval in System Settings when registering with `SMAppService`.
- Gatekeeper: none for a locally built bundle.

### Assumptions I made

- "External mouse" means any USB or Bluetooth HID device with Generic Desktop / Mouse usage that is not built in and not a touch pad.
- The user is fine with a private-framework call and accepts that it may break in a future macOS; the fallback chain and a visible warning state are the mitigation.
- Magic Mouse is treated as a mouse unless the user says otherwise.
- I did not change the scroll preference, register a login item, or unplug devices, to stay within the boundaries given.

### Not verified

- That `setSwipeScrollDirection` actually inverts scrolling on macOS 27.0.1 and that System Settings redraws live (symbol, signature and disassembly confirmed only).
- Removal callbacks on unplug or Bluetooth disconnect.
- Bluetooth mouse and Magic Trackpad property values on this OS (none present).
- `SMAppService.register()` under ad-hoc signing.
- `swift build` flow under Command Line Tools.
- That no TCC dialog appeared visually during the bundle probe.

## Sources

- https://shadowfacts.net/2021/scrollswitcher/ (ScrollSwitcher write-up, notification and private function discovery; read in full)
- https://git.shadowfacts.net/shadowfacts/ScrollSwitcher/commit/4403fb8eca215c8b684a3fc76436dcdb00b48953 (commit referenced in search results; the page returned HTTP 403 to me, so I used the search summary only)
- https://github.com/BrChung/.dotfiles/blob/HEAD/scripts/set_scroll_direction.swift
- https://github.com/jackharvest/NaturalOnBattery/blob/HEAD/main.swift
- https://github.com/leongmichael/scroll-swap/blob/HEAD/Sources/ScrollSwap/ScrollDirectionController.swift
- https://github.com/snosrap/DynamicScrollDirection/blob/HEAD/DynamicScrollDirection/main.m
- https://github.com/invainn/dotfiles/blob/HEAD/scroll-switcher/.local/bin/set-scroll-direction.swift
- https://github.com/abhip1008/scrollswitch (README, `Sources/ScrollSwitchCore/Monitors/DeviceMonitor.swift`, `Sources/ScrollSwitchCore/Support/LaunchAtLogin.swift`, `Resources/Info.plist`, `Makefile`)
- https://github.com/dongzhenye/reverse-scroll-cli/blob/HEAD/docs/research.md
- https://github.com/pilotmoon/Scroll-Reverser
- https://github.com/Caldis/Mos and https://github.com/linearmouse/linearmouse (descriptions only)
- https://github.com/blacktop/ipsw-diffs (macOS 27.0 listing containing the notification string)
- https://github.com/torvalds/linux/blob/master/drivers/hid/hid-ids.h (Apple vendor and Magic device IDs)
- https://github.com/khronokernel/DarwinDumped (IORegistry dump of a Magic Trackpad, `MacPro/MacPro6,1/IORegistry/IOregViewer/Resources/dataFiles/IOService/data1371.txt`)
- https://developer.apple.com/forums/thread/735999 and https://developer.apple.com/forums/thread/124368 (reports of the Input Monitoring prompt on enumeration; unanswered)
- https://developer.apple.com/forums/thread/744577 (`kIOReturnNotPermitted` from `IOHIDManagerOpen`; seen in search results only)
- https://git.axiodl.com/encounter/SDL/commit/172865ff137532123ec06177119be163ba1811f5 (SDL: denial is detectable only by opening)
- https://opensource.apple.com/source/IOKitUser/IOKitUser-1445.1.3/hid.subproj/IOHIDManager.h.auto.html (IOHIDManager header; NULL matching enumerates all devices)
- Apple forum threads on `SMAppService.status` returning `.notFound`, found through search at https://developer.apple.com/forums/tags/servicemanagement (I paraphrased from the search summary and did not open a specific thread, so treat that wording as unconfirmed)
- Local: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/IOKit.framework/Headers/hid/` (`IOHIDKeys.h`, `IOHIDDeviceKeys.h`, `IOHIDManager.h`), `man launchd.plist`
