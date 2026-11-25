import AppKit
import ApplicationServices

let museBundleID = "com.meta.endo"

// Everything this app asks of Muse goes through here. It reads only the
// identified call avatar window ("VoiceCallPictureInPicture"), never the chat.
// It writes two things: a press on a named call control, when the user clicks
// its button, and the avatar window's position (see ViewerController.tuck).
final class MuseCall {
    struct Control {
        let element: AXUIElement
        let label: String
        let frame: CGRect
    }
    struct State {
        let window: AXUIElement
        let frame: CGRect          // the avatar window, screen points, top-left origin
        var card: CGRect           // the picture inside it, same coordinates
        var microphone: Control?
        var speaker: Control?
        var endCall: Control?
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

    func state() -> State? {
        guard trusted, let app = NSRunningApplication.runningApplications(withBundleIdentifier: museBundleID).first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement],
              let window = windows.first(where: { attribute($0, kAXIdentifierAttribute) as? String == "VoiceCallPictureInPicture" }),
              let windowFrame = frame(window) else { return nil }
        var result = State(window: window, frame: windowFrame, card: windowFrame)
        var pending = [window]
        var examined = 0
        while let element = pending.popLast(), examined < 80 {
            examined += 1
            let id = attribute(element, kAXIdentifierAttribute) as? String ?? ""
            if id == "voice-call-picture-in-picture", let card = frame(element), windowFrame.contains(card) {
                result.card = card
            } else if ["voice-call-microphone-control", "voice-call-speaker-control", "voice-call-end-control"].contains(id),
                      let controlFrame = frame(element) {
                let control = Control(element: element, label: attribute(element, kAXDescriptionAttribute) as? String ?? "", frame: controlFrame)
                if id == "voice-call-microphone-control" { result.microphone = control }
                else if id == "voice-call-speaker-control" { result.speaker = control }
                else { result.endCall = control }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children)
            }
        }
        return result
    }

    // Resolve each click afresh; never send a coordinate click to another app.
    // A timeout is ambiguous, so never automatically retry a toggle.
    enum Action { case microphone, speaker, endCall }
    func press(_ action: Action) -> Bool {
        guard let current = state() else { return false }
        let control: Control?
        switch action {
        case .microphone: control = current.microphone
        case .speaker: control = current.speaker
        case .endCall: control = current.endCall
        }
        guard let control else { return false }
        return AXUIElementPerformAction(control.element, kAXPressAction as CFString) == .success
    }

    func move(_ state: State, to origin: CGPoint) -> Bool {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(state.window, kAXPositionAttribute as CFString, value) == .success
    }
}
