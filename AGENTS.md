# Muse Fullscreen

Keep this a minimal native Mac viewer: the existing Muse avatar window, full screen.
No web server, phone pairing, new agent, camera, microphone, or audio capture.
Use native ScreenCaptureKit and accept only one untitled portrait window owned by Muse.
Never fall back to capturing a display or the chat window.
Change microphone/speaker mute only from an explicit user click on its named control.
Never end the source call automatically. Escape hides the viewer and leaves its menu-bar shortcut running.
Use Accessibility actions only on identified Muse call controls. No coordinate injection or chat traversal.
Verify with the real call. A compile or a synthetic picture is not a completed live test.
