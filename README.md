# Muse Fullscreen

A small native Mac app that shows the Muse call avatar in its own ordinary window,
as large as that window is. A window manager can tile or resize it like any app.

## Use

1. Start a call in Muse.
2. Open **Muse Fullscreen.app** on the same desktop (the same OMAC page) as Muse's
   own window. The picture appears by itself.
3. The three round buttons over the picture press Muse's own speaker, microphone
   and end-call controls.
4. **Escape** (or the close button) hides the window. **Enlarge Muse** in the menu
   bar shows it again and holds the options and Quit.

## What Muse allows, measured on a live call (2026-11-24)

These are Muse's rules, not this app's. They decide when there is a picture.

- Muse shows its large avatar only while **Muse is the app you are using** and its
  own window is open (not minimized). In any other case it swaps to a small panel
  and the picture here stops. This window then says it is waiting, and resumes by
  itself, usually within a second, when the avatar returns.
- Because opening or clicking this app makes it the active one, it hands the
  keyboard back to Muse: 2.5 seconds after opening, and right after a click in its
  window. It does that only when Muse's own window is open on this desktop.
- The avatar window is 442 x 686 points at most (Muse's own "Make video window
  larger" stops there). The picture inside it is 332 x 568 pixels on a 1x screen.
  That is the best source there is. This app captures only that picture and
  enlarges it with a Lanczos filter and light sharpening.
- The capture keeps running at about 25 frames a second when the avatar window is
  covered, or slid off the screen edge with 40 points left on screen. It stops when
  the window is hidden.

**Move Muse's small avatar aside while showing** (menu bar, on by default) slides
Muse's floating avatar to the right screen edge while the picture is showing here,
and puts it back when this window is hidden, minimized or closed.

## Permissions

Screen Recording shows the avatar. Accessibility lets the buttons press Muse's
controls, finds the picture inside the avatar window, and moves the small avatar
aside. There is no recording, web server, camera, microphone or audio capture.
Audio stays in Muse. Nothing ends or starts a call by itself.

## Build

`./build.sh` needs Xcode command-line tools and an installed Apple Development
signing identity (or `MUSE_CODESIGN_IDENTITY`). Keep the same identity across
builds so macOS keeps its approvals. Apple Silicon, macOS 15.2 or later.
Diagnostics (events and frame counts, never images) go to `.runtime/viewer.log`.

## Checked on a live call, and not

Checked: OMAC enrolled and tiled the window at 930 x 1002 next to Muse with no
size refusal (four launches); the picture ran for 30 seconds at 20 to 25 frames a
second; it stopped and resumed across an OMAC page switch; the small avatar moved
aside and back.

Not checked: the three buttons in this build (only the owner may change mute or end
a call); OMAC's fill-the-page key with this window; more than one display; a
Retina display.
