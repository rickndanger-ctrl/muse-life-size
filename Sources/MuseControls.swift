import AppKit
import ApplicationServices

// Only traverse the identified Muse picture-in-picture window, never its chat.
final class MuseControls {
    struct Control {
        let element: AXUIElement
        let label: String
        let frame: CGRect?
    }
    struct Snapshot {
        let window: AXUIElement
        let microphone: Control?
        let speaker: Control?
        let endCall: Control?
    }
    var trusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    func snapshot() -> Snapshot? {
        guard trusted, let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.meta.endo" }) else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement],
              let window = windows.first(where: { attribute($0, kAXIdentifierAttribute) as? String == "VoiceCallPictureInPicture" }) else { return nil }
        var microphone: Control?
        var speaker: Control?
        var endCall: Control?
        var pending = [window]
        var examined = 0
        while let element = pending.popLast(), examined < 80 {
            examined += 1
            let id = attribute(element, kAXIdentifierAttribute) as? String ?? ""
            if ["voice-call-microphone-control", "voice-call-speaker-control", "voice-call-end-control"].contains(id) {
                let label = attribute(element, kAXDescriptionAttribute) as? String ?? ""
                let value = Control(element: element, label: label, frame: frame(element))
                if id == "voice-call-microphone-control" { microphone = value }
                else if id == "voice-call-speaker-control" { speaker = value }
                else { endCall = value }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children)
            }
        }
        guard microphone != nil || speaker != nil else { return nil }
        return Snapshot(window: window, microphone: microphone, speaker: speaker, endCall: endCall)
    }

    func raiseAvatar() {
        guard let current = snapshot() else { return }
        _ = AXUIElementPerformAction(current.window, kAXRaiseAction as CFString)
    }

    // Resolve each click afresh; never send a coordinate click to another app.
    // A timeout is ambiguous, so never automatically retry a toggle.
    enum Action { case microphone, speaker, endCall }
    func press(_ action: Action) -> Bool {
        guard let current = snapshot() else { return false }
        let control: Control?
        switch action {
        case .microphone: control = current.microphone
        case .speaker: control = current.speaker
        case .endCall: control = current.endCall
        }
        guard let control else { return false }
        return AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success
    }
}
