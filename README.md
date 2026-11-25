# Muse Fullscreen

A small native Mac app that shows the Muse call avatar in a free, see-through
window of its own: no frame, no background, any size, anywhere on the screen.

## Use

1. Open **Muse Fullscreen.app** and start a call in Muse, in either order. The
   picture appears by itself.
2. Drag the picture to move it. Drag an edge to resize it; it keeps its shape.
   **Double-click** it to fill the screen height, and again to go back.
3. The three round buttons over the picture press Muse's own speaker, microphone
   and end-call controls.
4. **Escape** (after a click on the picture) hides it. **Enlarge Muse** in the menu
   bar, or a right-click on the picture, shows it again and holds the options and
   Quit.

It is not tied to Muse's window or to an OMAC page. OMAC does not manage it, so it
stays where it is when the page changes.

## What Muse allows, measured on a live call (2026-11-24)

These are Muse's rules, not this app's. They decide how sharp the picture is.

- Muse shows its **large avatar** (332 x 568 pixels of picture inside a 442 x 686
  window; its own "Make video window larger" stops there) only while Muse is the
  app you are using and its own window is open. That is the sharp source.
- In every other case (another app in use, another page, Muse's window minimized)
  Muse shows a **small call panel** instead, with the same avatar at about
  144 x 226 pixels. This app follows it, so the picture keeps going, but it is
  visibly softer when enlarged. Nothing can make Muse draw it larger.
- A click on this window does not take the keyboard from Muse. Opening the app
  does, so it hands the keyboard back to Muse half a second later, only when
  Muse's own window is open on this desktop.
- The capture keeps running at about 25 frames a second when the source window is
  covered, or slid off the screen edge with 40 points left on screen. It stops when
  the window is hidden, and resumes by itself.
- The white backdrop behind the avatar is part of Muse's picture. Everything
  around it is see-through.

**Move Muse's small avatar aside while showing** (menu, on by default) slides
Muse's large floating avatar to the right screen edge while the picture is showing
here, and puts it back when this window is hidden.

## Permissions

Screen Recording shows the avatar. Accessibility lets the buttons press Muse's
controls, finds the picture inside the avatar window, and moves the small avatar
aside. There is no recording, web server, camera, microphone or audio capture.
Audio stays in Muse. Nothing ends or starts a call by itself.

## Build

`./build.sh` needs Xcode command-line tools and an installed Apple Development
signing identity (or `MUSE_CODESIGN_IDENTITY`). Keep the same identity across
builds so macOS keeps its approvals. Apple Silicon, macOS 15.2 or later.
Diagnostics (events and frame counts, never images) go to `~/Library/Logs/Muse Fullscreen/viewer.log`, wherever the app is kept.

## Checked, and not

Checked on a live call (earlier builds, same capture code): about 25 frames a
second from the large avatar; stop and resume across an OMAC page switch; the
microphone button; the small avatar moving aside and back.

Checked without a call (this build): the window is see-through and frameless;
OMAC writes no row for it and it stays in place across three page switches.

Not checked yet: the picture in this build, from either source; the crop of the
small call panel (worked out from one measurement); see-through corners; the
double-click fill; more than one display; a Retina display.
