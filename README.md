# Muse Fullscreen

A small native Mac app that displays the exact live Muse avatar window full screen.

1. Open your voice call in Muse.
2. Open **Muse Fullscreen.app** and click **Make Muse full screen**.
3. On first use, allow Muse Fullscreen in macOS Screen Recording settings.
   Then click its button again; it finds the floating avatar automatically.

The app enters full screen after it receives a real video frame. It preserves
the portrait proportions, with black space at the sides. Escape closes the viewer;
the original Muse call and its mute settings remain in Muse. Use the original
Muse window to change call controls.

Only a single untitled portrait window belonging to Muse is accepted. The app displays it locally;
there is no recording, web server, phone connection, microphone, camera, or audio
capture. Closing the viewer ends its window capture. The original window's
resolution determines sharpness when enlarged.

Build with `./build.sh` using Xcode command-line tools. Requires an Apple Silicon
Mac running macOS 15.2 or later. This is a normal foreground app, with no background
agent or startup service.

Validation: native window-picker flow did not deliver a capture. Replaced with
auto-detection of only the Muse avatar via ScreenCaptureKit. Live capture and
Escape verification are pending macOS Screen Recording permission.
