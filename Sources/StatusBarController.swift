import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let audioDeviceManager = AudioDeviceManager()
    private let inputMeter = InputMeter()

    private var inputLevelItem: NSMenuItem?
    private var outputVolumeItem: NSMenuItem?

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        inputMeter.onLevelUpdate = { [weak self] level in
            self?.updateInputLevel(level)
        }
    }

    func install() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Mic")
            button.imagePosition = .imageLeading
            button.title = "Mic"
            button.toolTip = "IsMyMicOn"
        }
        statusItem.isVisible = true
        rebuildMenu()
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        if MicPermission.isGranted {
            inputMeter.start()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        inputMeter.stop()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        addInputSection()
        menu.addItem(.separator())
        addOutputSection()
        menu.addItem(.separator())
        addQuitItem()
    }

    private func addInputSection() {
        menu.addItem(makeSectionHeader("Input Devices"))

        if MicPermission.isGranted {
            let item = NSMenuItem(title: "Input Level: --", action: nil, keyEquivalent: "")
            item.isEnabled = false
            inputLevelItem = item
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Mic access required for level meter", action: #selector(requestMicAccess), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let devices = audioDeviceManager.inputDevices()
        let activeDevice = audioDeviceManager.defaultInputDevice()
        if devices.isEmpty {
            menu.addItem(disabledItem("No input devices found"))
            return
        }

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectInputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            if device == activeDevice {
                item.state = .on
            }
            menu.addItem(item)
        }
    }

    private func addOutputSection() {
        menu.addItem(makeSectionHeader("Output Devices"))

        let volumeTitle: String
        if let volume = audioDeviceManager.outputVolume() {
            volumeTitle = "Output Volume: \(Int(volume * 100))%"
        } else {
            volumeTitle = "Output Volume: --"
        }

        let volumeItem = NSMenuItem(title: volumeTitle, action: nil, keyEquivalent: "")
        volumeItem.isEnabled = false
        outputVolumeItem = volumeItem
        menu.addItem(volumeItem)

        let devices = audioDeviceManager.outputDevices()
        let activeDevice = audioDeviceManager.defaultOutputDevice()
        if devices.isEmpty {
            menu.addItem(disabledItem("No output devices found"))
            return
        }

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectOutputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            if device == activeDevice {
                item.state = .on
            }
            menu.addItem(item)
        }
    }

    private func addQuitItem() {
        let item = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        item.target = self
        menu.addItem(item)
    }

    private func makeSectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func updateInputLevel(_ level: Float) {
        let clamped = max(0, min(1, level))
        let percentage = Int(clamped * 100)
        DispatchQueue.main.async { [weak self] in
            self?.inputLevelItem?.title = "Input Level: \(percentage)%"
        }
    }

    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDevice else { return }
        audioDeviceManager.setDefaultInputDevice(device)
        rebuildMenu()
    }

    @objc private func selectOutputDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDevice else { return }
        audioDeviceManager.setDefaultOutputDevice(device)
        rebuildMenu()
    }

    @objc private func requestMicAccess() {
        MicPermission.requestAccess { [weak self] _ in
            DispatchQueue.main.async {
                self?.rebuildMenu()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
