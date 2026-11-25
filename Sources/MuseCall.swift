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
        let large: Bool            // the large avatar, not the small call panel
        let frame: CGRect          // that window, screen points, top-left origin
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

    // Muse shows the large avatar ("VoiceCallPictureInPicture") only while Muse
    // is the active app and its own window is open. Otherwise it shows a small
    // call panel ("AmbientPanel") with the same avatar and the same controls.
    func state() -> State? {
        guard trusted, let app = NSRunningApplication.runningApplications(withBundleIdentifier: museBundleID).first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        func find(_ id: String) -> AXUIElement? { windows.first { attribute($0, kAXIdentifierAttribute) as? String == id } }
        let large = find("VoiceCallPictureInPicture")
        guard let window = large ?? find("AmbientPanel"), let windowFrame = frame(window) else { return nil }
        var result = State(window: window, large: large != nil, frame: windowFrame, card: windowFrame)
        var foundCard = false
        var controlsLeft = CGFloat.infinity     // includes controls this app has no button for (captions)
        var pending = [window]
        var examined = 0
        while let element = pending.popLast(), examined < 80 {
            examined += 1
            let id = attribute(element, kAXIdentifierAttribute) as? String ?? ""
            if id.hasPrefix("voice-call-"), id.hasSuffix("-control"), let any = frame(element) { controlsLeft = min(controlsLeft, any.minX) }
            if id == "voice-call-picture-in-picture", let card = frame(element), windowFrame.contains(card) {
                result.card = card
                foundCard = true
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
        if large == nil {
            // The small panel names no picture element. Its picture sits above
            // and around the row of controls: 8 points of margin, from the top
            // of the panel to just under the controls.
            let controls = [result.microphone, result.speaker, result.endCall].compactMap { $0?.frame }
            guard windowFrame.height >= 250, let end = result.endCall?.frame, let left = controls.map(\.minX).min() else { return nil }
            let x = max(windowFrame.minX, min(left, controlsLeft) - 8)
            let card = CGRect(x: x, y: windowFrame.minY + 8, width: end.maxX + 8 - x, height: end.maxY + 6 - windowFrame.minY - 8)
            guard windowFrame.contains(card), card.width > 60, card.height > 100 else { return nil }
            result.card = card
        } else if !foundCard { return nil }
        return result
    }

    // Muse shows its large avatar only while Muse is the active app. True when
    // a call is up and Muse's own window is open here, so bringing Muse
    // forward shows the avatar without disturbing another page.
    func canShowAvatar() -> Bool {
        guard trusted, let app = NSRunningApplication.runningApplications(withBundleIdentifier: museBundleID).first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] else { return false }
        let ids = windows.map { attribute($0, kAXIdentifierAttribute) as? String ?? "" }
        let mainOpen = windows.contains { attribute($0, kAXIdentifierAttribute) as? String == "hatch-full" && attribute($0, kAXMinimizedAttribute) as? Bool == false }
        return mainOpen && (ids.contains("AmbientPanel") || ids.contains("VoiceCallPictureInPicture"))
    }

    // Resolve each click afresh; never send a coordinate click to another app.
    // A timeout is ambiguous, so never automatically retry a toggle.
    enum Action { case microphone, speaker, endCall }
    func press(_ action: Action) -> Bool {
        // Muse draws the same named controls in its large avatar window and in
        // the small panel it shows while another app is active.
        guard trusted, let app = NSRunningApplication.runningApplications(withBundleIdentifier: museBundleID).first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        let wanted: String
        switch action {
        case .microphone: wanted = "voice-call-microphone-control"
        case .speaker: wanted = "voice-call-speaker-control"
        case .endCall: wanted = "voice-call-end-control"
        }
        let windows = (attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            ["VoiceCallPictureInPicture", "AmbientPanel"].contains(attribute($0, kAXIdentifierAttribute) as? String ?? "")
        }
        var pending = windows
        var examined = 0
        while let element = pending.popLast(), examined < 120 {
            examined += 1
            if attribute(element, kAXIdentifierAttribute) as? String == wanted {
                return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] { pending.append(contentsOf: children) }
        }
        return false
    }

    func move(_ state: State, to origin: CGPoint) -> Bool {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(state.window, kAXPositionAttribute as CFString, value) == .success
    }
}
