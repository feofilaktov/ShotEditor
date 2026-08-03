# Changelog

All notable changes to ShotEditor are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-08-02

First public release. A local-first macOS screenshot capture & annotation tool.

### Capture
- Area, window, and full-screen capture (global shortcuts `⌥⌘4` / `⌥⌘5` / `⌥⌘3`)
- Delayed capture (3 / 5 / 10 s), repeat last capture
- Open existing PNG/JPEG (`⌘O`)
- Eyedropper (copies hex color)

### Annotation tools
- Arrow (3 styles, shadow, dashed)
- Shapes: rectangle, rounded rectangle, ellipse, line, star (stroke or fill, dashed)
- Pen and Highlighter (semi-transparent)
- Numbered step markers
- Text (auto-growing editor, background color)
- Callout speech bubble with auto-contrast text
- Redaction: Blur / Pixelate / Solid (tuned to make text truly unreadable)
- Crop with 8 resize handles, move, and rule-of-thirds guides
- Select, move, and resize any object; layer ordering via right-click
- Single-key tool shortcuts, full undo/redo

### Image & export
- Rotate, flip, resize the whole image
- Backdrop: padding + gradient/solid background + rounded corners + shadow
- Save as PNG or JPEG, copy to clipboard, drag-out to Finder/other apps
- OCR: copy recognized text (`⇧⌘T`)

### App
- Menu-bar agent (no Dock icon), Light / Dark / System appearance
- Auto-save to a chosen folder, Recent Screenshots history
- Launch at login
- Universal binary (Apple Silicon + Intel), macOS 13+

### Notes
- Distributed unsigned; first launch requires right-click → Open.
- Requires Screen Recording permission (as any screenshot tool does).
