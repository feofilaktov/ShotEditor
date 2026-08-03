import AppKit

// ShotEditor — a standalone screenshot annotation tool.
// Runs as a menu-bar agent (LSUIElement); no cloud/account dependencies.

// Icon generation hook (used by build.sh): render a 1024px PNG and exit.
if let idx = CommandLine.arguments.firstIndex(of: "--makeicon") {
    let out = (idx + 1 < CommandLine.arguments.count) ? CommandLine.arguments[idx + 1] : "AppIcon-1024.png"
    IconMaker.writePNG(to: out)
    exit(0)
}

if CommandLine.arguments.contains("--checkperm") {
    let ok = CGPreflightScreenCaptureAccess()
    FileHandle.standardOutput.write("screen-recording-granted: \(ok)\n".data(using: .utf8)!)
    exit(ok ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent, no Dock icon
app.run()
