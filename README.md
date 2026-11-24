# Muse Fullscreen

A small native Mac app that displays the exact live Muse avatar window full screen.

1. Open your voice call in Muse and show its floating avatar (Window > Focus video window).
2. Open **Muse Fullscreen.app** and click **Make Muse full screen**.
3. On first use, allow Muse Fullscreen in macOS Screen Recording settings.
   Then click its button again; it finds the floating avatar automatically.

The app fills the current screen after it receives a real video frame, without
switching macOS Spaces. It preserves
the portrait proportions, with black space at the sides. Escape closes the viewer;
the original Muse call and its mute settings remain in Muse. Use the original
Muse window to change call controls.

Only a single untitled portrait window belonging to Muse is accepted. The app displays it locally;
there is no recording, web server, phone connection, microphone, camera, or audio
capture. Closing the viewer ends its window capture. The original window's
resolution determines sharpness when enlarged.

Build with `./build.sh` using Xcode command-line tools and a stable installed
Apple Development signing identity (or set `MUSE_CODESIGN_IDENTITY`). Keep that
identity across rebuilds so macOS can retain the approval. Requires an Apple Silicon
Mac running macOS 15.2 or later. This is a normal foreground app, with no background
agent or startup service.

Validation: stable signing retained capture permission after a rebuild. The actual
muted Muse avatar appeared in native full screen, but the picture subsequently
went black; Escape quit the viewer. Replaced the Space transition with a borderless
window covering the current screen. Muse later reported Voice call ended. Sustained
live capture with the revised presentation and source-call preservation still need
verification with a reopened call.
