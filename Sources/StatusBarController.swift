import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let audioDeviceManager = AudioDeviceManager()
    private let inputMeter = InputMeter()
    private let statusContentView = StatusItemContentView()

    private var inputLevelItem: NSMenuItem?
    private var outputVolumeItem: NSMenuItem?
    private let showVirtualDevicesKey = "ShowVirtualAudioDevices"

    private var showVirtualDevices: Bool {
        get { UserDefaults.standard.bool(forKey: showVirtualDevicesKey) }
        set { UserDefaults.standard.set(newValue, forKey: showVirtualDevicesKey) }
    }

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
            button.title = ""
            button.image = nil
            button.toolTip = "IsMyMicOn"
            statusContentView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(statusContentView)
            NSLayoutConstraint.activate([
                statusContentView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                statusContentView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                statusContentView.topAnchor.constraint(equalTo: button.topAnchor),
                statusContentView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
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
        addOptionsSection()
        menu.addItem(.separator())
        addQuitItem()
        updateStatusText()
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

        let devices = audioDeviceManager.inputDevices(includeVirtual: showVirtualDevices)
        let activeDevice = audioDeviceManager.defaultInputDevice()
        if devices.isEmpty {
            menu.addItem(disabledItem("No input devices found"))
            return
        }

        if let activeDevice, !devices.contains(activeDevice), !showVirtualDevices {
            menu.addItem(disabledItem("Active input hidden: \(activeDevice.name)"))
        }

        for device in devices {
            let item = makeActionItem(
                title: device.name,
                isChecked: device == activeDevice,
                action: #selector(selectInputDevice(_:)),
                representedObject: device
            )
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

        let devices = audioDeviceManager.outputDevices(includeVirtual: showVirtualDevices)
        let activeDevice = audioDeviceManager.defaultOutputDevice()
        if devices.isEmpty {
            menu.addItem(disabledItem("No output devices found"))
            return
        }

        if let activeDevice, !devices.contains(activeDevice), !showVirtualDevices {
            menu.addItem(disabledItem("Active output hidden: \(activeDevice.name)"))
        }

        for device in devices {
            let item = makeActionItem(
                title: device.name,
                isChecked: device == activeDevice,
                action: #selector(selectOutputDevice(_:)),
                representedObject: device
            )
            menu.addItem(item)
        }
    }

    private func addQuitItem() {
        let item = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        item.target = self
        menu.addItem(item)
    }

    private func addOptionsSection() {
        let item = makeActionItem(
            title: "Show Virtual Devices",
            isChecked: showVirtualDevices,
            action: #selector(toggleVirtualDevices),
            representedObject: nil
        )
        menu.addItem(item)
    }

    private func makeActionItem(title: String, isChecked: Bool, action: Selector, representedObject: Any?) -> NSMenuItem {
        let button = MenuActionButton(title: title, isChecked: isChecked)
        button.target = self
        button.action = action
        button.representedObject = representedObject
        let item = NSMenuItem()
        item.view = button
        return item
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

    private func updateStatusText() {
        let inputName = audioDeviceManager.defaultInputDevice()?.name ?? "--"
        let outputName = audioDeviceManager.defaultOutputDevice()?.name ?? "--"
        let inputText = "In: \(shortDeviceName(inputName))"
        let outputText = "Out: \(shortDeviceName(outputName))"
        statusContentView.update(inputText: inputText, outputText: outputText)
        statusItem.length = statusContentView.intrinsicContentSize.width
    }

    private func shortDeviceName(_ name: String) -> String {
        if name == "--" {
            return name
        }

        var result = name
        let replacements: [(String, String)] = [
            ("MacBook Pro", "MBP"),
            ("MacBook Air", "MBA"),
            ("MacBook", "MB"),
            ("Microphone", "Mic"),
            ("Speakers", "Spk"),
            ("Headphones", "HP"),
            ("Headset", "HS")
        ]

        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        let maxLength = 18
        if result.count > maxLength {
            let endIndex = result.index(result.startIndex, offsetBy: maxLength - 3)
            result = String(result[..<endIndex]) + "..."
        }

        return result
    }

    @objc private func selectInputDevice(_ sender: Any?) {
        guard let button = sender as? MenuActionButton,
              let device = button.representedObject as? AudioDevice else { return }
        audioDeviceManager.setDefaultInputDevice(device)
        rebuildMenu()
    }

    @objc private func selectOutputDevice(_ sender: Any?) {
        guard let button = sender as? MenuActionButton,
              let device = button.representedObject as? AudioDevice else { return }
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

    @objc private func toggleVirtualDevices() {
        showVirtualDevices.toggle()
        rebuildMenu()
    }
}
