# Muse Fullscreen

A small native Mac viewer for the existing Muse avatar call.

1. Open **Muse Fullscreen.app** once. It keeps an **Enlarge Muse** shortcut on the right side of the menu bar.
2. Start your call in Muse, then click the menu-bar shortcut to enlarge it.
   The shortcut stays available while this app runs; it dims when no visible avatar is found.
3. Click the enlarged microphone button to unmute yourself and the speaker button
   to hear Muse. The red phone button ends the original call when clicked.
4. **Escape** or **Back** hides the enlarged view and leaves the shortcut running.
   Right-click the shortcut for options and Quit.

**Transparent background** reveals the desktop around the portrait. Uncheck it
for black sides. Muse's own white portrait backdrop remains part of the original
picture. The viewer fills the current screen below the menu bar without switching
macOS Spaces. It keeps the original proportions; source resolution limits sharpness.

Screen Recording permission is required to display the avatar. Accessibility
permission is required for interactive call buttons. Use **Enable call controls…**
to open setup. The viewer presses only the named controls in Muse's identified
picture-in-picture window. It can use Muse's **Focus video window** menu command
when you request full screen; it does not start calls. If the avatar remains hidden,
show it in Muse with **Window → Focus video window** and retry.

There is no recording, web server, phone connection, camera, microphone capture,
or duplicate audio stream. Audio stays in Muse. Microphone/speaker states change
only on explicit control clicks. Hiding the viewer stops capture. When the source
avatar disappears, the enlarged view returns to the desktop.

Build with `./build.sh` using Xcode command-line tools and a stable installed
Apple Development signing identity (or set `MUSE_CODESIGN_IDENTITY`). Keep that
identity across builds to retain macOS approval. Requires an Apple Silicon Mac
running macOS 15.2 or later. No login item or background agent is installed; this
is a user-launched GUI app which remains running for its menu-bar shortcut.

Live validation on 2026-11-24 displayed the real avatar at 1920 × 1080 and logged
90 rendered frames. The enlarged microphone button changed Muse’s control label
from Unmute to Mute and back. The speaker button was verified both ways in the
earlier live test. Both controls were restored to mute. The end-call button and
spoken audio were not exercised. Escape hides the viewer while its menu-bar
shortcut stays running. Native macOS full-screen Spaces previously produced a
black picture, so this viewer stays on the current desktop.
