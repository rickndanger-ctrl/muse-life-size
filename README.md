# Muse Fullscreen

A small native Mac viewer for the existing Muse avatar call.

1. Open **Muse Fullscreen.app** once. It keeps a **Muse** shortcut in the menu bar.
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

Live validation on 2026-11-24: captured the real muted Muse avatar, displayed moving
frames, and logged 90 rendered frames. Enlarged speaker button changed the actual
Muse label from Unmute speaker to Mute speaker and back; microphone remained muted.
Tested the transparent/black background setting. Escape hid the viewer while the
process stayed running. A subsequent UI inspection reopened it through macOS's
app-reopen callback. End-call and microphone transmission were not exercised.
The final hidden-avatar menu fallback and physical menu-bar icon click still need
live verification. The last call timed out during testing. Native macOS full-screen
Spaces previously produced a black picture, so this viewer stays on the current desktop.
