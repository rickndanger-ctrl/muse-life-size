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

Validation (2026-11-24): stable signing retained capture permission after a rebuild.
The revised viewer displayed the actual muted avatar at 1920 × 1080 on the current
desktop. Separate screenshots showed the avatar blinking and moving, with the
picture still visible after the initial frame. Capture ran for 16 seconds before
Escape quit the viewer; Muse still reported Voice call is live afterward. Microphone
and speaker controls were not changed. This was a short live smoke test, not a
long-duration call test. The earlier macOS Space transition showed a black picture,
so the viewer now covers the existing desktop instead.
