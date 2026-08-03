# Architecture

ShotEditor is a native **Swift + AppKit** menu-bar agent (`LSUIElement`) built
with SwiftPM. It has no third-party dependencies; annotations render with Core
Graphics and OCR uses Vision.

## Runtime flow

```
menu-bar agent (AppDelegate)
   └─ capture (screencapture) ──▶ EditorWindowController
                                     ├─ CanvasView  (mouse, tools, undo, crop, text)
                                     │     └─ EditorDocument (base image + [Annotation])
                                     └─ Renderer / ImageExport (flatten, transforms, save/copy)
```

- `main.swift` boots `NSApplication` as an accessory agent, and handles dev
  flags (`--makeicon`, `--selftest`, `--showcase`, `--demo`, `--checkperm`).
- `AppDelegate` owns the status-bar menu, global hotkeys, capture routing,
  appearance/recents/autosave/launch-at-login, and Screen Recording permission.

## Source map (`Sources/ShotEditor/`)

| Path | Responsibility |
|------|----------------|
| `main.swift` | App entry, dev-flag dispatch |
| `AppDelegate.swift` | Menu-bar item, hotkeys, capture routing, prefs, permission |
| `Capture/ScreenCapture.swift` | Wraps `/usr/sbin/screencapture` (area/window/full) |
| `Capture/HotkeyManager.swift` | Carbon global hotkeys |
| `Model/Annotation.swift` | Abstract annotation base + geometry helpers + `TextEditable` |
| `Model/Annotations.swift` | Arrow, Shape, Pen/Highlighter, Number, Text, Callout, Blur |
| `Model/Tool.swift` | `ToolKind` + shared `ToolSettings` |
| `Model/Palette.swift` | Color swatches |
| `Model/Backdrop.swift` | Export backdrop (padding/gradient/shadow) |
| `Model/RecentScreenshots.swift` | Recent-files store |
| `Editor/EditorDocument.swift` | Base image + annotation stack, hit-testing |
| `Editor/CanvasView.swift` | Rendering, mouse handling, undo/redo, crop, text edit, layers |
| `Editor/EditorWindowController.swift` | Toolbar, inspector, zoom, export, image ops, OCR |
| `Export/Renderer.swift` | Flatten to bitmap, crop, rotate/flip/scale, backdrop compositing |
| `Export/ImageExport.swift` | PNG/JPEG encode, save panel, pasteboard |
| `UI/Theme.swift` | Design tokens (metrics, colors, materials) |
| `UI/Controls.swift` | `IconButton`, `IconSegmentedBar`, button factories |
| `UI/SwatchBar.swift` | Circular color swatches |
| `UI/DragWell.swift` | Drag-out of the flattened image |
| `UI/IconMaker.swift` | Programmatic app icon (built at package time) |

## Key design choices

- **Annotations live in image-space** (bottom-left origin, base-image points).
  `CanvasView` applies a zoom+backdrop transform; export uses the same model via
  `Renderer`, so on-screen and saved output match.
- **Exact-pixel rendering.** `Renderer` composites into an explicit
  `NSBitmapImageRep` and transforms via `CGContext`, avoiding the backing-scale
  doubling that `NSImage.cgImage(forProposedRect:)` / cached `CIContext` can cause
  on Retina (guarded by `RendererTests`).
- **Undo** is snapshot-based (clone the annotation stack) through the window's
  `UndoManager`.
- **Redaction** (`BlurAnnotation`) scales block/blur strength to the region so
  text becomes genuinely unreadable; `Solid` is unrecoverable.

## Tests

`Tests/ShotEditorTests/` — geometry & hit-testing, resize handles, flatten/crop/
rotate/flip/scale sizes, redaction efficacy, PNG/JPEG export, backdrop sizing,
document model, and OCR. Run with `make test`.
