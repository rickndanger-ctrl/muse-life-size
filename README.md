# Muse Fullscreen

A small native Mac app that displays the exact live Muse avatar window full screen.

1. Open your voice call in Muse.
2. Open **Muse Fullscreen.app** and click **Make Muse full screen**.
3. In macOS's window picker, choose the floating Muse avatar and confirm sharing.

The app enters full screen after it receives a real video frame. It preserves
the portrait proportions, with black space at the sides. Escape closes the viewer;
the original Muse call and its mute settings remain in Muse. Use the original
Muse window to change call controls.

Only the selected Muse avatar window is accepted. The app displays it locally;
there is no recording, web server, phone connection, microphone, camera, or audio
capture. Closing the viewer ends its window capture. The original window's
resolution determines sharpness when enlarged.

Build with `./build.sh` using Xcode command-line tools. Requires an Apple Silicon
Mac running macOS 15.2 or later. This is a normal foreground app, with no background
agent or startup service.

Validation: built and locally code-signed successfully; launched the real app and
opened/cancelled the native single-window picker. Live Muse capture and Escape
behavior remain pending the user's window-sharing approval and a reopened call.
