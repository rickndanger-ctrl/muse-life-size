import AppKit
import ScreenCaptureKit
import AVFoundation
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

final class ViewerWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

final class PictureView: NSView {
    let display = AVSampleBufferDisplayLayer()
    var sourceSize = CGSize(width: 442, height: 686)
    var onLayout: (() -> Void)?
    var videoRect: CGRect {
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        display.videoGravity = .resizeAspect
        display.isOpaque = false
        display.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(display)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.frame = videoRect
        CATransaction.commit()
        onLayout?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         SCStreamOutput, SCStreamDelegate {
    private var window: ViewerWindow!
    private let picture = PictureView(frame: .zero)
    private let startPanel = NSStackView()
    private let message = NSTextField(wrappingLabelWithString: "Open your Muse call.\nThis app finds the avatar and makes it full screen.")
    private let choose = NSButton(title: "Make Muse full screen", target: nil, action: nil)
    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "local.muse.fullscreen.frames", qos: .userInteractive)
    private var frames = 0
    private var generation = 0
    private var firstFrameTimeout: DispatchWorkItem?
    private var starting = false
    private var expanded = false
    private var originalFrame = NSRect.zero
    private let callControls = MuseControls()
    private var statusItem: NSStatusItem!
    private var updateTimer: Timer?
    private var discoveryRunning = false
    private var avatarAvailable = false
    private var sourceFrame = CGRect.zero
    private var currentControls: MuseControls.Snapshot?
    private let toolbar = NSStackView()
    private let enableControls = NSButton(title: "Enable call controls…", target: nil, action: nil)
    private let microphone = NSButton()
    private let speaker = NSButton()
    private let endCall = NSButton()
    private var transparent = UserDefaults.standard.object(forKey: "transparent") as? Bool ?? true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let showItem = applicationMenu.addItem(withTitle: "Open full screen", action: #selector(toggleViewer), keyEquivalent: "f")
        showItem.target = self
        let controlsItem = applicationMenu.addItem(withTitle: "Enable call controls…", action: #selector(requestControls), keyEquivalent: "")
        controlsItem.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Muse Fullscreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        appMenu.addItem(applicationItem)
        NSApp.mainMenu = appMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Muse"
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Muse full screen")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = "Open Muse full screen. Right-click for options."

        window = ViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 290),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Muse Fullscreen"
        window.delegate = self
        window.onEscape = { [weak self] in self?.hideViewer() }
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = .black
        window.contentView = picture
        window.minSize = NSSize(width: 420, height: 260)
        window.center()

        let title = NSTextField(labelWithString: "Your Muse, full screen.")
        title.font = .systemFont(ofSize: 25, weight: .medium)
        title.textColor = .white
        message.font = .systemFont(ofSize: 14)
        message.textColor = .lightGray
        message.alignment = .center
        let hint = NSTextField(labelWithString: "Escape returns to your desktop. Use Muse in the menu bar to reopen.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .lightGray
        choose.bezelStyle = .rounded
        choose.controlSize = .large
        choose.target = self
        choose.action = #selector(chooseWindow)
        startPanel.orientation = .vertical
        startPanel.alignment = .centerX
        startPanel.spacing = 20
        let setupControls = NSButton(title: "Enable call controls…", target: self, action: #selector(requestControls))
        setupControls.bezelStyle = .rounded
        [title, message, choose, setupControls, hint].forEach { startPanel.addArrangedSubview($0) }
        startPanel.translatesAutoresizingMaskIntoConstraints = false
        picture.addSubview(startPanel)
        configureControls()
        NSLayoutConstraint.activate([
            startPanel.centerXAnchor.constraint(equalTo: picture.centerXAnchor),
            startPanel.centerYAnchor.constraint(equalTo: picture.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        diagnostic("viewer launched; no capture active")
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func configureControls() {
        toolbar.orientation = .horizontal
        toolbar.spacing = 10
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        toolbar.layer?.cornerRadius = 10
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let back = NSButton(title: "Back · Esc", target: self, action: #selector(hideViewer))
        let background = NSButton(checkboxWithTitle: "Transparent background", target: self, action: #selector(toggleBackground))
        background.state = transparent ? .on : .off
        enableControls.target = self
        enableControls.action = #selector(requestControls)
        [back, background, enableControls].forEach { toolbar.addArrangedSubview($0) }
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        picture.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: picture.centerXAnchor),
            toolbar.topAnchor.constraint(equalTo: picture.topAnchor, constant: 8)
        ])
        toolbar.isHidden = true
        for (button, action, label) in [
            (microphone, #selector(toggleMicrophone), "Microphone"),
            (speaker, #selector(toggleSpeaker), "Speaker"),
            (endCall, #selector(endSourceCall), "End call")
        ] {
            button.target = self
            button.action = action
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(white: 0.92, alpha: 1).cgColor
            button.layer?.cornerRadius = 13
            button.setAccessibilityLabel(label)
            button.isHidden = true
            picture.addSubview(button)
        }
        picture.onLayout = { [weak self] in self?.layoutControls() }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = menu.addItem(withTitle: expanded ? "Return to desktop" : "Open full screen", action: #selector(toggleViewer), keyEquivalent: "")
            open.target = self
            let controls = menu.addItem(withTitle: "Enable call controls…", action: #selector(requestControls), keyEquivalent: "")
            controls.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Muse Fullscreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { toggleViewer() }
    }

    @objc private func toggleViewer() {
        if expanded { hideViewer(); return }
        callControls.raiseAvatar()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        chooseWindow()
    }

    private func refresh() {
        currentControls = callControls.snapshot()
        enableControls.isHidden = callControls.trusted
        layoutControls()
        guard !discoveryRunning, CGPreflightScreenCaptureAccess() else { return }
        discoveryRunning = true
        Task { @MainActor in
            defer { discoveryRunning = false }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            let candidates = content.windows.filter(isAvatar)
            avatarAvailable = candidates.count == 1
            statusItem.button?.appearsDisabled = !avatarAvailable && !expanded
            if let source = candidates.first, candidates.count == 1 { sourceFrame = source.frame }
            if expanded && !avatarAvailable { hideViewer() }
        }
    }

    private func isAvatar(_ source: SCWindow) -> Bool {
        source.owningApplication?.bundleIdentifier == "com.meta.endo"
        && (source.title ?? "").isEmpty && source.frame.width >= 100
        && source.isOnScreen && source.windowLayer == 3
        && source.frame.height > source.frame.width * 1.45
        && source.frame.height < source.frame.width * 2.2
    }

    private func layoutControls() {
        guard expanded, sourceFrame.width > 0, sourceFrame.height > 0 else {
            [microphone, speaker, endCall].forEach { $0.isHidden = true }
            return
        }
        let rect = picture.videoRect
        for (button, control, fallback) in [
            (microphone, currentControls?.microphone, "mic"),
            (speaker, currentControls?.speaker, "speaker.wave.2"),
            (endCall, currentControls?.endCall, "phone.down.fill")
        ] {
            guard let control, let frame = control.frame else { button.isHidden = true; continue }
            let centerX = rect.minX + (frame.midX - sourceFrame.minX) / sourceFrame.width * rect.width
            let centerY = rect.maxY - (frame.midY - sourceFrame.minY) / sourceFrame.height * rect.height
            guard rect.contains(CGPoint(x: centerX, y: centerY)) else { button.isHidden = true; continue }
            let side = max(32, min(48, frame.height / sourceFrame.height * rect.height))
            button.frame = CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
            let muted = control.label.lowercased().hasPrefix("unmute")
            let symbol = button === microphone ? (muted ? "mic.slash.fill" : "mic.fill")
                : button === speaker ? (muted ? "speaker.slash.fill" : "speaker.wave.2.fill") : fallback
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: control.label)
            button.contentTintColor = button === endCall || (button === microphone && muted) ? .systemRed : .labelColor
            button.toolTip = control.label
            button.setAccessibilityLabel(control.label)
            button.isHidden = false
        }
    }

    @objc private func requestControls() {
        guard !callControls.trusted else { refresh(); return }
        callControls.requestPermission()
        let alert = NSAlert()
        alert.messageText = "Let the buttons control Muse"
        alert.informativeText = "Enable Muse Fullscreen in System Settings → Privacy & Security → Accessibility. This lets these buttons press Muse’s microphone, speaker, and end-call controls. It does not give this viewer microphone access."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleMicrophone() { performControl(.microphone) }
    @objc private func toggleSpeaker() { performControl(.speaker) }
    @objc private func endSourceCall() { performControl(.endCall) }
    private func performControl(_ action: MuseControls.Action) {
        guard callControls.trusted else { requestControls(); return }
        let succeeded = callControls.press(action)
        diagnostic("user call-control action \(action); acknowledged=\(succeeded)")
        if succeeded && action == .endCall { hideViewer() }
        refresh()
    }

    @objc private func toggleBackground(_ sender: NSButton) {
        transparent = sender.state == .on
        UserDefaults.standard.set(transparent, forKey: "transparent")
        applyBackground()
    }
    private func applyBackground() {
        let clear = expanded && transparent
        window.isOpaque = !clear
        window.backgroundColor = clear ? .clear : .black
        window.hasShadow = !expanded
        picture.layer?.backgroundColor = (clear ? NSColor.clear : NSColor.black).cgColor
    }

    @objc private func hideViewer() {
        generation += 1
        firstFrameTimeout?.cancel()
        let old = stream
        stream = nil
        if let old { Task { try? await old.stopCapture() } }
        picture.display.flushAndRemoveImage()
        starting = false
        choose.isEnabled = true
        startPanel.isHidden = false
        toolbar.isHidden = true
        restoreWindow()
        layoutControls()
        window.orderOut(nil)
        diagnostic("viewer hidden; menu-bar shortcut remains; source call unchanged")
    }

    @objc private func chooseWindow() {
        guard !starting, stream == nil else { return }
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.meta.endo" }) else {
            message.stringValue = "Open a call in Muse first, then try again."
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            diagnostic("requesting macOS screen-capture permission")
            _ = CGRequestScreenCaptureAccess()
            message.stringValue = "Allow Muse Fullscreen in macOS Screen Recording settings, then click the button again."
            return
        }
        starting = true
        choose.isEnabled = false
        message.stringValue = "Finding the Muse avatar…"
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let museWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == "com.meta.endo" }
                // The chat has a title. The call is an untitled, portrait floating window.
                // Require a single exact candidate rather than choosing any other window.
                let candidates = museWindows.filter(isAvatar)
                diagnostic("Muse windows: \(museWindows.count); avatar candidates: \(candidates.count)")
                for source in museWindows {
                    diagnostic("Muse window untitled=\((source.title ?? "").isEmpty) size=\(Int(source.frame.width))x\(Int(source.frame.height)) layer=\(source.windowLayer) visible=\(source.isOnScreen)")
                }
                starting = false
                guard candidates.count == 1 else {
                    showError(candidates.isEmpty
                        ? "Open Muse’s floating avatar call window, then click the button again."
                        : "More than one Muse avatar window was found. Leave only your call window open and try again.")
                    return
                }
                let source = candidates[0]
                sourceFrame = source.frame
                diagnostic("capturing only Muse avatar window \(source.windowID)")
                start(filter: SCContentFilter(desktopIndependentWindow: source))
            } catch {
                diagnostic("window lookup failed: \((error as NSError).code)")
                showError("macOS could not access the Muse window. Check Screen Recording permission for Muse Fullscreen.")
            }
        }
    }

    private func start(filter: SCContentFilter) {
        guard !starting, stream == nil else { return }
        starting = true
        choose.isEnabled = false
        message.stringValue = "Opening the live Muse picture…"
        generation += 1
        let currentGeneration = generation
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(2, Int(filter.contentRect.width * scale))
        config.height = max(2, Int(filter.contentRect.height * scale))
        picture.sourceSize = CGSize(width: config.width, height: config.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.captureMicrophone = false
        config.ignoreShadowsSingleWindow = true
        config.ignoreGlobalClipSingleWindow = true
        let capture = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = capture
        frames = 0
        Task { @MainActor in
            do {
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
                try await capture.startCapture()
                guard generation == currentGeneration, self.stream === capture else { return }
                diagnostic("capture started; video only; \(config.width)x\(config.height)")
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self, self.frames == 0, self.stream === capture else { return }
                    self.showError("No live picture arrived. Keep the Muse call window open and try again.")
                }
                firstFrameTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
            } catch {
                guard generation == currentGeneration else { return }
                diagnostic("capture failed: \((error as NSError).code)")
                showError("The Muse window could not be shared. Keep its call open and try again.")
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        if let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(array, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            if self.picture.display.status == .failed { self.picture.display.flush() }
            self.picture.display.enqueue(sampleBuffer)
            self.frames += 1
            if self.frames == 1 {
                self.firstFrameTimeout?.cancel()
                self.starting = false
                self.startPanel.isHidden = true
                self.toolbar.isHidden = false
                self.window.title = "Muse Fullscreen — live"
                self.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.fillCurrentScreen()
                self.refresh()
                diagnostic("first live frame displayed")
            } else if self.frames == 90 {
                diagnostic("90 live frames displayed; renderer status \(self.picture.display.status.rawValue)")
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            diagnostic("source stopped: \((error as NSError).code)")
            self.showError("The shared window stopped. Open the Muse call and choose it again.")
        }
    }

    private func showError(_ text: String) {
        diagnostic("viewer error: \(text)")
        generation += 1
        firstFrameTimeout?.cancel()
        let old = stream
        stream = nil
        if let old { Task { try? await old.stopCapture() } }
        picture.display.flushAndRemoveImage()
        starting = false
        choose.isEnabled = true
        startPanel.isHidden = false
        toolbar.isHidden = true
        message.stringValue = text
        window.title = "Muse Fullscreen"
        restoreWindow()
    }

    private func fillCurrentScreen() {
        guard !expanded, let screen = window.screen ?? NSScreen.main else { return }
        originalFrame = window.frame
        expanded = true
        // Keep Muse on the same desktop. A separate full-screen Space can hide
        // its floating avatar and leave the captured picture black.
        window.styleMask = [.borderless]
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        // Keep the menu bar accessible while making the portrait screen-height.
        NSApp.presentationOptions = [.autoHideDock]
        let topInset = screen.frame.maxY - screen.visibleFrame.maxY
        var frame = screen.frame
        frame.size.height -= topInset
        window.setFrame(frame, display: true)
        applyBackground()
        window.makeKeyAndOrderFront(nil)
        diagnostic("filled current screen; \(Int(screen.frame.width))x\(Int(screen.frame.height))")
    }

    private func restoreWindow() {
        guard expanded else { return }
        expanded = false
        applyBackground()
        NSApp.presentationOptions = []
        window.level = .normal
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setFrame(originalFrame, display: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hideViewer(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !expanded { toggleViewer() }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        firstFrameTimeout?.cancel()
        updateTimer?.invalidate()
        diagnostic("viewer closed; source call unchanged")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
