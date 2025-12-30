import AVFoundation
import AppKit

enum MicPermission {
    static var isGranted: Bool {
        authorizationStatus() == .authorized
    }

    static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
    }

    static func openSystemSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return false
        }
        NSApp.activate(ignoringOtherApps: true)
        if NSWorkspace.shared.open(url) {
            return true
        }
        let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        return NSWorkspace.shared.open(appURL)
    }
}
