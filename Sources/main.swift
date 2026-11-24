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
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } else { super.keyDown(with: event) }
    }
}

final class PictureView: NSView {
    let display = AVSampleBufferDisplayLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        display.videoGravity = .resizeAspect
        layer?.addSublayer(display)
        setAccessibilityElement(true)
        setAccessibilityLabel("Live enlarged Muse call. Press Escape to close this view.")
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override func layout() { super.layout(); display.frame = bounds }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    private var window: ViewerWindow!
    private let picture = PictureView(frame: .zero)
    private let startPanel = NSStackView()
    private let message = NSTextField(wrappingLabelWithString: "Choose the small Muse avatar window.\nIt will fill the screen as soon as the live picture arrives.")
    private let choose = NSButton(title: "Make Muse full screen", target: nil, action: nil)
    private var stream: SCStream?
    private let captureQueue = DispatchQueue(label: "local.muse.fullscreen.frames", qos: .userInteractive)
    private var frames = 0
    private var generation = 0
    private var firstFrameTimeout: DispatchWorkItem?
    private var starting = false
    private var pickerOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Muse Fullscreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        appMenu.addItem(applicationItem)
        NSApp.mainMenu = appMenu

        window = ViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 290),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Muse Fullscreen"
        window.delegate = self
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
        let hint = NSTextField(labelWithString: "Escape closes this view. Your call stays in Muse.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .lightGray
        choose.bezelStyle = .rounded
        choose.controlSize = .large
        choose.target = self
        choose.action = #selector(chooseWindow)
        startPanel.orientation = .vertical
        startPanel.alignment = .centerX
        startPanel.spacing = 20
        [title, message, choose, hint].forEach { startPanel.addArrangedSubview($0) }
        startPanel.translatesAutoresizingMaskIntoConstraints = false
        picture.addSubview(startPanel)
        NSLayoutConstraint.activate([
            startPanel.centerXAnchor.constraint(equalTo: picture.centerXAnchor),
            startPanel.centerYAnchor.constraint(equalTo: picture.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
        SCContentSharingPicker.shared.add(self)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        diagnostic("viewer launched; no capture active")
    }

    @objc private func chooseWindow() {
        guard !starting else { return }
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.meta.endo" }) else {
            message.stringValue = "Open a call in Muse first, then try again."
            return
        }
        Task { @MainActor in
            // This API returns only content this process may already access. It does
            // not request general Screen Recording permission or capture a display.
            if let content = try? await SCShareableContent.currentProcess {
                let candidates = content.windows.filter(Self.isAvatar)
                diagnostic("already-authorized avatar windows: \(candidates.count)")
                if candidates.count == 1 {
                    self.start(filter: SCContentFilter(desktopIndependentWindow: candidates[0]))
                    return
                }
            }
            self.presentPicker()
        }
    }

    private static func isAvatar(_ source: SCWindow) -> Bool {
        source.owningApplication?.bundleIdentifier == "com.meta.endo"
            && (source.title ?? "").isEmpty
            && source.frame.width >= 100
            && source.frame.height > source.frame.width * 1.3
    }

    private func presentPicker() {
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.allowsChangingSelectedContent = false
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier!]
        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
        picker.isActive = true
        pickerOpen = true
        diagnostic("single-window picker presented")
        picker.present(using: .window)
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            self.pickerOpen = false
            diagnostic("picker cancelled; active capture: \(self.stream != nil)")
            guard self.stream == nil else { return }
            self.message.stringValue = "Nothing is being shared. Choose the avatar window when ready."
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { self.showError("macOS could not open the window picker. Try again.") }
        diagnostic("picker failed: \((error as NSError).code)")
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for oldStream: SCStream?) {
        DispatchQueue.main.async {
            self.pickerOpen = false
            let selected = filter.includedWindows
            diagnostic("picker selected \(selected.count) windows; style \(filter.style.rawValue)")
            for source in selected {
                diagnostic("selected source app=\(source.owningApplication?.bundleIdentifier ?? "unknown") untitled=\((source.title ?? "").isEmpty) size=\(Int(source.frame.width))x\(Int(source.frame.height)) layer=\(source.windowLayer)")
            }
            // Muse's floating call is an untitled portrait window. Never capture the main chat.
            guard selected.count == 1, let source = selected.first,
                  Self.isAvatar(source) else {
                self.showError("Choose the small floating Muse avatar, rather than its chat window.")
                return
            }
            self.start(filter: filter)
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
                self.window.title = "Muse Fullscreen — live"
                self.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                if !self.window.styleMask.contains(.fullScreen) { self.window.toggleFullScreen(nil) }
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
        message.stringValue = text
        window.title = "Muse Fullscreen"
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }

    func windowDidEnterFullScreen(_ notification: Notification) { diagnostic("native full screen entered") }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        firstFrameTimeout?.cancel()
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        diagnostic("viewer closed; source call unchanged")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
