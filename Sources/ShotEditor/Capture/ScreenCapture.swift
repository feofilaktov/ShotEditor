import AppKit

/// Wraps the system `screencapture` tool. Using the OS tool means we inherit
/// the native selection UI and permissions handling for free.
enum ScreenCapture {

    enum Mode {
        case area          // interactive rectangular selection
        case window        // interactive window selection
        case fullScreen    // whole main display, no interaction
    }

    static func capture(mode: Mode, completion: @escaping (NSImage?) -> Void) {
        let tmp = NSTemporaryDirectory() + "shot-\(UUID().uuidString).png"

        var args: [String]
        switch mode {
        case .area:       args = ["-i", "-o", "-x"]
        case .window:     args = ["-w", "-o", "-x"]
        case .fullScreen: args = ["-x"]
        }
        args.append(tmp)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = args

        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { try? FileManager.default.removeItem(atPath: tmp) }
                guard FileManager.default.fileExists(atPath: tmp),
                      let image = NSImage(contentsOfFile: tmp) else {
                    // User cancelled the selection — nothing to do.
                    completion(nil)
                    return
                }
                completion(image)
            }
        }

        do {
            try task.run()
        } catch {
            NSLog("screencapture failed: \(error)")
            completion(nil)
        }
    }
}
