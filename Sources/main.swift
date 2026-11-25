import AppKit
import ScreenCaptureKit
import MetalKit
import CoreImage
import CoreMedia

// Local diagnostics contain only lifecycle events and frame counts, never images.
func diagnostic(_ message: String) {
    let directory = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".runtime", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let file = directory.appendingPathComponent("viewer.log")
    if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    guard let handle = try? FileHandle(forWritingTo: file) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data("\(Date().ISO8601Format()) \(message)\n".utf8))
}

// Draws the newest frame as large as the view allows, keeping its shape.
// The source is small (about 332 x 568 pixels), so it is enlarged with a
// Lanczos filter and lightly sharpened instead of plain smoothing.
final class PictureView: MTKView, MTKViewDelegate {
    private let commands: MTLCommandQueue
    private let context: CIContext
    private var image: CIImage?
    private(set) var pictureRect = CGRect.zero   // where the picture is, in view points

    init() {
        let device = MTLCreateSystemDefaultDevice()!
        commands = device.makeCommandQueue()!
        context = CIContext(mtlDevice: device)
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) not used") }

    var hasPicture: Bool { image != nil }
    func show(_ buffer: CVPixelBuffer?) {
        image = buffer.map { CIImage(cvPixelBuffer: $0) }
        if image == nil { pictureRect = .zero }
        needsDisplay = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let size = drawableSize
        guard size.width >= 1, size.height >= 1, let drawable = currentDrawable,
              let buffer = commands.makeCommandBuffer() else { return }
        var output = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        if let image, image.extent.width > 0, image.extent.height > 0 {
            let scale = min(size.width / image.extent.width, size.height / image.extent.height)
            var scaled = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
            if scale > 1 { scaled = scaled.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.4]) }
            scaled = scaled.transformed(by: CGAffineTransform(translationX: ((size.width - scaled.extent.width) / 2 - scaled.extent.minX).rounded(),
                                                              y: ((size.height - scaled.extent.height) / 2 - scaled.extent.minY).rounded()))
            output = scaled.composited(over: output)
            let points = bounds.width / size.width
            pictureRect = CGRect(x: scaled.extent.minX * points, y: scaled.extent.minY * points,
                                 width: scaled.extent.width * points, height: scaled.extent.height * points)
        }
        let destination = CIRenderDestination(width: Int(size.width), height: Int(size.height),
                                              pixelFormat: colorPixelFormat, commandBuffer: buffer) { drawable.texture }
        _ = try? context.startTask(toRender: output, to: destination)
        buffer.present(drawable)
        buffer.commit()
    }
}

final class ViewerWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

// A click works even when another app (Muse) is the active one.
final class CallButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ContainerView: NSView {
    var onLayout: (() -> Void)?
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { onClick?() }
    override func layout() { super.layout(); onLayout?() }
}

final class ViewerController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate,
                              SCStreamOutput, SCStreamDelegate {
    private var window: ViewerWindow!
    private let container = ContainerView()
    private let picture = PictureView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let permission = NSButton(title: "Allow Screen Recording…", target: nil, action: nil)
    private let microphone = CallButton()
    private let speaker = CallButton()
    private let endCall = CallButton()
    private var statusItem: NSStatusItem!
    private let muse = MuseCall()
    private var timer: Timer?

    private var shown = false
    private var stream: SCStream?
    private var starting = false
    private var capturedCard = CGSize.zero
    private let frameQueue = DispatchQueue(label: "local.muse.fullscreen.frames", qos: .userInteractive)
    private var frames = 0
    private var lastAlive: TimeInterval = 0
    private var started: TimeInterval = 0
    private var ticks = 0
    private var wasReceiving = false
    private var call: MuseCall.State?

    // The small avatar's place before this app moved it aside. Saved so a
    // crash cannot leave it stranded at the screen edge.
    private var tuckAvatar = UserDefaults.standard.object(forKey: "tuckAvatar") as? Bool ?? true
    private var avatarHome: CGPoint? = (UserDefaults.standard.array(forKey: "avatarHome") as? [Double]).flatMap {
        $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil
    } {
        didSet { UserDefaults.standard.set(avatarHome.map { [Double($0.x), Double($0.y)] }, forKey: "avatarHome") }
    }

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var receiving: Bool { stream != nil && uptime - lastAlive < 2.5 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Muse Fullscreen", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Muse Fullscreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.mainMenu = mainMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Enlarge Muse"
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Muse Fullscreen")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // An ordinary window: a window manager may move and resize it freely.
        window = ViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Muse Fullscreen"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 160, height: 160)
        window.onEscape = { [weak self] in self?.hide() }
        window.contentView = container
        window.center()

        message.alignment = .center
        message.textColor = .lightGray
        message.font = .systemFont(ofSize: 14)
        permission.bezelStyle = .rounded
        permission.target = self
        permission.action = #selector(askForScreenRecording)
        container.addSubview(picture)
        container.addSubview(message)
        container.addSubview(permission)
        for (button, action) in [(microphone, #selector(toggleMicrophone)), (speaker, #selector(toggleSpeaker)), (endCall, #selector(endSourceCall))] {
            button.target = self
            button.action = action
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(white: 0.94, alpha: 1).cgColor
            button.isHidden = true
            container.addSubview(button)
        }
        container.onLayout = { [weak self] in self?.layoutContents() }
        container.onClick = { [weak self] in self?.returnToMuse(after: 0.1) }

        diagnostic("viewer launched")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        show()
    }

    // MARK: Showing and hiding

    @objc private func show() {
        shown = true
        window.makeKeyAndOrderFront(nil)
        tick()
        // Opening this app makes it the active one, and Muse then hides its
        // avatar. Wait long enough for a window manager to place this window,
        // then hand the keyboard back to Muse.
        returnToMuse(after: 2.5)
    }

    // Muse shows its large avatar only while Muse is the active app. Called
    // after this app was opened or clicked; never brings Muse to another page.
    private func returnToMuse(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.shown, NSApp.isActive, self.muse.canShowAvatar(),
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: museBundleID).first else { return }
            NSApp.yieldActivation(to: app)
            diagnostic("handed the keyboard back to Muse; accepted=\(app.activate())")
        }
    }

    @objc private func hide() {
        guard shown else { return }
        shown = false
        stopStream()
        picture.show(nil)
        tuck()
        window.orderOut(nil)
        diagnostic("viewer hidden; menu-bar shortcut remains; source call unchanged")
    }

    @objc private func toggle() { shown ? hide() : show() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func windowDidMiniaturize(_ notification: Notification) { tuck() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !shown { show() } else if window.isMiniaturized { window.deminiaturize(nil) }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        shown = false
        call = muse.state()
        tuck()
        diagnostic("viewer closed; source call unchanged")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: shown ? "Hide viewer" : "Show viewer", action: #selector(toggle), keyEquivalent: "").target = self
        let aside = menu.addItem(withTitle: "Move Muse’s small avatar aside while showing", action: #selector(toggleTuck), keyEquivalent: "")
        aside.target = self
        aside.state = tuckAvatar ? .on : .off
        if !muse.trusted {
            menu.addItem(withTitle: "Enable call buttons…", action: #selector(askForAccessibility), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Muse Fullscreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    // MARK: Once a second

    private func tick() {
        ticks += 1
        call = muse.state()
        if shown {
            if let stream, let call, capturedCard != .zero, abs(call.card.width - capturedCard.width) > 2 {
                diagnostic("avatar changed size; restarting capture")
                stop(stream)
            } else if stream != nil, call != nil, uptime - max(lastAlive, started) > 6 {
                diagnostic("avatar is showing but no frames arrive; restarting capture")
                stopStream()
            }
            if stream == nil, !starting, CGPreflightScreenCaptureAccess() { findAvatar() }
        }
        if receiving != wasReceiving {
            wasReceiving = receiving
            diagnostic(receiving ? "live picture showing" : "picture stopped: avatar not on screen")
            if !receiving { picture.show(nil) }
        }
        if receiving, ticks % 30 == 0 {
            diagnostic("live; \(frames) frames in 30 s; shown at \(Int(picture.pictureRect.width))x\(Int(picture.pictureRect.height))")
            frames = 0
        }
        tuck()
        layoutContents()
    }

    private func layoutContents() {
        let bounds = container.bounds
        picture.frame = bounds
        let live = receiving && picture.hasPicture
        message.isHidden = live
        permission.isHidden = live || CGPreflightScreenCaptureAccess()
        if !live {
            if !CGPreflightScreenCaptureAccess() {
                message.stringValue = "Muse Fullscreen needs Screen Recording permission to show the avatar."
            } else if NSRunningApplication.runningApplications(withBundleIdentifier: museBundleID).isEmpty {
                message.stringValue = "Muse is not open."
            } else {
                message.stringValue = "Waiting for Muse’s avatar.\n\nMuse shows it only during a call, while Muse is the app you are using and its window is open on this page. Click Muse’s window to bring it back."
            }
            let width = max(80, min(bounds.width - 32, 380))
            let height = message.sizeThatFits(NSSize(width: width, height: 400)).height
            message.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
            permission.sizeToFit()
            permission.frame.origin = NSPoint(x: (bounds.width - permission.frame.width) / 2, y: message.frame.minY - permission.frame.height - 12)
        }
        // The three buttons sit exactly over Muse's own controls in the picture.
        let rect = picture.pictureRect
        for (button, control, normal, off) in [
            (microphone, call?.microphone, "mic.fill", "mic.slash.fill"),
            (speaker, call?.speaker, "speaker.wave.2.fill", "speaker.slash.fill"),
            (endCall, call?.endCall, "phone.down.fill", "phone.down.fill")
        ] {
            guard live, let call, let control, rect.width > 0, call.card.width > 0 else { button.isHidden = true; continue }
            let zoom = rect.width / call.card.width
            let side = max(24, min(64, control.frame.height * zoom))
            let x = rect.minX + (control.frame.midX - call.card.minX) * zoom
            let y = rect.maxY - (control.frame.midY - call.card.minY) * zoom
            button.frame = NSRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
            button.layer?.cornerRadius = side / 2
            let isOff = control.label.lowercased().hasPrefix("unmute")
            button.image = NSImage(systemSymbolName: isOff ? off : normal, accessibilityDescription: control.label)
            button.contentTintColor = button === endCall || isOff ? .systemRed : .darkGray
            button.toolTip = control.label
            button.setAccessibilityLabel(control.label)
            button.isHidden = false
        }
    }

    // MARK: Muse's small avatar

    // The capture needs Muse's avatar window on screen, but it floats above
    // every ordinary window. While the picture is showing here, slide it to
    // the right screen edge so only its empty margin stays on screen. Put it
    // back whenever this window is not showing the picture.
    private func tuck() {
        guard let call else { return }
        let edge = NSScreen.screens.map(\.frame.maxX).max() ?? call.frame.maxX
        let aside = edge - 40
        let isAside = abs(call.frame.minX - aside) < 2
        let want = tuckAvatar && shown && !window.isMiniaturized && receiving
        if want, !isAside {
            avatarHome = call.frame.origin
            if muse.move(call, to: CGPoint(x: aside, y: call.frame.minY)) { diagnostic("small avatar moved aside") }
        } else if !want, isAside {
            let home = avatarHome ?? CGPoint(x: edge - call.frame.width - 20, y: call.frame.minY)
            if muse.move(call, to: home) { avatarHome = nil; diagnostic("small avatar put back") }
        }
    }

    @objc private func toggleTuck() {
        tuckAvatar.toggle()
        UserDefaults.standard.set(tuckAvatar, forKey: "tuckAvatar")
        tuck()
    }

    // MARK: Capture

    // Accept only one untitled portrait floating window owned by Muse.
    private func isAvatar(_ source: SCWindow) -> Bool {
        source.owningApplication?.bundleIdentifier == museBundleID
        && (source.title ?? "").isEmpty && source.windowLayer == 3 && source.isOnScreen
        && source.frame.width >= 100
        && source.frame.height > source.frame.width * 1.45
        && source.frame.height < source.frame.width * 2.2
    }

    private func findAvatar() {
        starting = true
        Task { @MainActor in
            defer { starting = false }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
            let candidates = content.windows.filter(isAvatar)
            guard shown, stream == nil, candidates.count == 1, let source = candidates.first else { return }
            let filter = SCContentFilter(desktopIndependentWindow: source)
            let config = SCStreamConfiguration()
            var crop = CGRect(origin: .zero, size: source.frame.size)
            capturedCard = .zero
            // Capture only the picture, not the empty margin around it.
            if let call = muse.state(), abs(call.frame.width - source.frame.width) <= 2, abs(call.frame.height - source.frame.height) <= 2 {
                crop = call.card.offsetBy(dx: -call.frame.minX, dy: -call.frame.minY)
                config.sourceRect = crop
                capturedCard = call.card.size
            }
            let scale = CGFloat(filter.pointPixelScale)
            config.width = max(2, Int(crop.width * scale))
            config.height = max(2, Int(crop.height * scale))
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 4
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.capturesAudio = false
            config.captureMicrophone = false
            config.ignoreShadowsSingleWindow = true
            config.ignoreGlobalClipSingleWindow = true
            let capture = SCStream(filter: filter, configuration: config, delegate: self)
            do {
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
                try await capture.startCapture()
                guard shown, stream == nil else { try? await capture.stopCapture(); return }
                stream = capture
                started = uptime
                diagnostic("capturing only Muse avatar window \(source.windowID); video only; \(config.width)x\(config.height)")
            } catch {
                diagnostic("capture failed: \((error as NSError).code)")
            }
        }
    }

    private func stopStream() { if let stream { stop(stream) } }
    private func stop(_ old: SCStream) {
        if stream === old { stream = nil }
        Task { try? await old.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw),
              status == .complete || status == .idle else { return }
        let buffer = status == .complete ? CMSampleBufferGetImageBuffer(sampleBuffer) : nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.lastAlive = self.uptime
            guard let buffer else { return }
            self.frames += 1
            let first = !self.picture.hasPicture
            self.picture.show(buffer)
            if first { self.tick() }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            diagnostic("capture stopped: \((error as NSError).code)")
            self.stream = nil
        }
    }

    // MARK: Buttons

    @objc private func toggleMicrophone() { press(.microphone) }
    @objc private func toggleSpeaker() { press(.speaker) }
    @objc private func endSourceCall() { press(.endCall) }
    private func press(_ action: MuseCall.Action) {
        let succeeded = muse.press(action)
        diagnostic("user call-control action \(action); acknowledged=\(succeeded)")
        tick()
        returnToMuse(after: 0.1)
    }

    @objc private func askForScreenRecording() {
        diagnostic("requesting macOS screen-capture permission")
        _ = CGRequestScreenCaptureAccess()
    }
    @objc private func askForAccessibility() { muse.requestPermission() }
}

let app = NSApplication.shared
let controller = ViewerController()
app.setActivationPolicy(.regular)
app.delegate = controller
app.run()
