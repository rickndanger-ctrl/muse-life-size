# Muse Fullscreen

Keep this a minimal native Mac viewer: the existing Muse avatar, in one ordinary resizable window.
No floating or always-on-top window. A window manager must be able to tile and resize it.
No web server, phone pairing, new agent, camera, microphone, or audio capture.
Use native ScreenCaptureKit and accept only one untitled portrait window owned by Muse.
Never fall back to capturing a display or the chat window.
Change microphone/speaker mute only from an explicit user click on its named control.
Never end the source call automatically. Escape hides the viewer and leaves its menu-bar shortcut running.
Use Accessibility only on Muse's identified call windows: press their named call controls, read where the picture is,
and move the avatar window aside and back. No coordinate injection or chat traversal.
Bring Muse forward only when its own window is already open on this desktop; never pull it from another page.
Verify with the real call. A compile or a synthetic picture is not a completed live test.
