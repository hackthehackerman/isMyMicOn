import AppKit
import CoreAudio

final class StatusBarController: NSObject, NSMenuDelegate {
    private enum InputLevelStatus: Equatable {
        case idle
        case active
        case unavailable(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let audioDeviceManager = AudioDeviceManager()
    private let inputMeter = InputMeter()
    private let statusContentView = StatusItemContentView()

    private var inputLevelItem: NSMenuItem?
    private var outputVolumeItem: NSMenuItem?
    private let showVirtualDevicesKey = "ShowVirtualAudioDevices"
    private let systemObjectID = AudioObjectID(UInt32(kAudioObjectSystemObject))
    private let listenerQueue = DispatchQueue(label: "IsMyMicOn.AudioListeners")
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var isMenuOpen = false
    private var inputRetryTimer: DispatchSourceTimer?
    private var inputRetryAttempt = 0
    private let inputRetryDelays: [TimeInterval] = [2, 3, 5]
    private var inputLevelStatus: InputLevelStatus = .idle
    private var lastInputLevel: Float = 0

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
        startObservingDefaultDeviceChanges()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        rebuildMenu()
        if MicPermission.isGranted {
            startInputMeterWithRetry()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        setInputLevelStatus(.idle)
        inputMeter.stop()
        stopInputRetryTimer()
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
            applyInputLevelStatus()
        } else {
            let status = MicPermission.authorizationStatus()
            let title: String
            let action: Selector
            if status == .notDetermined {
                title = "Grant microphone access to show input level"
                action = #selector(requestMicAccess)
            } else {
                title = "Open Privacy Settings to allow microphone"
                action = #selector(openMicSettings)
            }

            let item = makeActionItem(
                title: title,
                isChecked: false,
                action: action,
                representedObject: nil
            )
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
        guard inputLevelStatus == .active else { return }
        let clamped = max(0, min(1, level))
        lastInputLevel = clamped
        let percentage = Int(clamped * 100)
        DispatchQueue.main.async { [weak self] in
            self?.inputLevelItem?.title = "Input Level: \(percentage)%"
        }
    }

    private func applyInputLevelStatus() {
        switch inputLevelStatus {
        case .active:
            updateInputLevel(lastInputLevel)
        case .idle:
            inputLevelItem?.title = "Input Level: --"
        case .unavailable(let message):
            inputLevelItem?.title = message
        }
    }

    private func setInputLevelStatus(_ status: InputLevelStatus) {
        inputLevelStatus = status
        applyInputLevelStatus()
    }

    private func inputLevelUnavailableTitle() -> String {
        guard let useState = audioDeviceManager.defaultInputDeviceUseState() else {
            return "Input Level: unavailable"
        }

        if useState.isHoggedByAnotherProcess || useState.isRunningSomewhere {
            return "Input Level: in use by another app"
        }

        return "Input Level: unavailable"
    }

    private func startInputMeterWithRetry() {
        stopInputRetryTimer()
        inputRetryAttempt = 0
        attemptStartInputMeter()
    }

    private func restartInputMeterForDeviceChange() {
        guard isMenuOpen, MicPermission.isGranted else { return }
        setInputLevelStatus(.idle)
        inputMeter.stop()
        startInputMeterWithRetry()
    }

    private func attemptStartInputMeter() {
        guard isMenuOpen, MicPermission.isGranted else { return }

        let deviceID = audioDeviceManager.defaultInputDevice()?.id ?? AudioObjectID(UInt32(kAudioObjectUnknown))
        if deviceID != AudioObjectID(UInt32(kAudioObjectUnknown)), inputMeter.start(deviceID: deviceID) {
            setInputLevelStatus(.active)
            stopInputRetryTimer()
            return
        }

        setInputLevelStatus(.unavailable(inputLevelUnavailableTitle()))
        scheduleInputRetry()
    }

    private func scheduleInputRetry() {
        guard isMenuOpen else { return }

        stopInputRetryTimer()
        let index = min(inputRetryAttempt, inputRetryDelays.count - 1)
        let delay = inputRetryDelays[index]
        inputRetryAttempt += 1

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.attemptStartInputMeter()
        }
        timer.resume()
        inputRetryTimer = timer
    }

    private func stopInputRetryTimer() {
        inputRetryTimer?.cancel()
        inputRetryTimer = nil
    }

    private func updateStatusText() {
        let inputName = audioDeviceManager.defaultInputDevice()?.name ?? "--"
        let outputName = audioDeviceManager.defaultOutputDevice()?.name ?? "--"
        let inputText = shortDeviceName(inputName, maxLength: 8)
        let outputText = shortDeviceName(outputName, maxLength: 8)
        statusContentView.update(inputText: inputText, outputText: outputText)
        statusItem.length = statusContentView.intrinsicContentSize.width
    }

    private func startObservingDefaultDeviceChanges() {
        let inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let inputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultInputChange()
        }
        let outputListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDefaultOutputChange()
        }

        defaultInputListener = inputListener
        defaultOutputListener = outputListener

        var mutableInput = inputAddress
        var mutableOutput = outputAddress
        AudioObjectAddPropertyListenerBlock(systemObjectID, &mutableInput, listenerQueue, inputListener)
        AudioObjectAddPropertyListenerBlock(systemObjectID, &mutableOutput, listenerQueue, outputListener)
    }

    private func handleDefaultInputChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateStatusText()
            if self.isMenuOpen {
                self.rebuildMenu()
                self.restartInputMeterForDeviceChange()
            }
        }
    }

    private func handleDefaultOutputChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateStatusText()
            if self.isMenuOpen {
                self.rebuildMenu()
            }
        }
    }

    private func shortDeviceName(_ name: String, maxLength: Int = 18) -> String {
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
        restartInputMeterForDeviceChange()
    }

    @objc private func selectOutputDevice(_ sender: Any?) {
        guard let button = sender as? MenuActionButton,
              let device = button.representedObject as? AudioDevice else { return }
        audioDeviceManager.setDefaultOutputDevice(device)
        rebuildMenu()
    }

    @objc private func requestMicAccess() {
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MicPermission.requestAccess { [weak self] _ in
                DispatchQueue.main.async {
                    self?.rebuildMenu()
                }
            }
        }
    }

    @objc private func openMicSettings() {
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = MicPermission.openSystemSettings()
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
