import AppKit
import Foundation
import IdasenKit
import SwiftUI

/// Developer helpers, enabled only when the matching command line flags are
/// passed. They allow verifying the UI without bringing windows to the front:
///
///     Idasen --demo --dev-snapshot ~/Desktop/idasen.png
///
/// `--dev-snapshot` renders every app window to PNG after the app has settled,
/// waits for a simulated move to finish when in demo mode, and quits.
@MainActor
enum DevTools {
    static var isSnapshotRun: Bool {
        CommandLine.arguments.contains("--dev-snapshot")
    }

    /// Preview processes never read or overwrite the user's settings or presets.
    static let previewDirectory: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Idasen-preview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var snapshotPath: String {
        guard let index = CommandLine.arguments.firstIndex(of: "--dev-snapshot"),
              index + 1 < CommandLine.arguments.count
        else {
            return "\(NSHomeDirectory())/Desktop/idasen-snapshot.png"
        }
        return CommandLine.arguments[index + 1]
    }

    /// Schedules a demo move (when in demo mode) followed by a window snapshot.
    static func runSnapshotSequence(model: AppModel) {
        let path = snapshotPath
        MainActor.assumeIsolated {
            model.banner = nil
            if let tab = argumentValue("--dev-tab").flatMap(SidebarItem.init(rawValue:)) {
                model.selection = tab
            } else {
                model.selection = .desk
            }

        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            MainActor.assumeIsolated {
                let size = (argumentValue("--dev-size") ?? "1080x720").split(separator: "x")
                if size.count == 2, let width = Double(size[0]), let height = Double(size[1]),
                   let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.setContentSize(NSSize(width: max(940, width), height: max(640, height)))
                }
                if model.isDemoMode, CommandLine.arguments.contains("--dev-moving") {
                    model.move(toHeightMM: 1100)
                }
            }
        }
        if CommandLine.arguments.contains("--dev-repeat") {
            Task { @MainActor in
                for index in 1...30 {
                    try? await Task.sleep(for: .seconds(2))
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    let repeated = url.deletingPathExtension().path + "-\(index)." + url.pathExtension
                    writeSnapshot(path: repeated)
                }
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            writeSnapshot(path: path)
            if CommandLine.arguments.contains("--dev-quit") {
                model.shutdown()
                exit(0)
            }
        }
    }

    static func argumentValue(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              index + 1 < CommandLine.arguments.count
        else { return nil }
        return CommandLine.arguments[index + 1]
    }

    static func writeSnapshot(path: String) {
        let candidates = NSApp.windows.filter { $0.isVisible && $0.frame.height > 200 }
        guard let window = candidates.first(where: { $0.canBecomeMain }) ?? candidates.first,
              let view = window.contentView
        else {
            FileHandle.standardError.write(Data("dev-snapshot: no visible window\n".utf8))
            return
        }

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            try data.write(to: url)
            FileHandle.standardError.write(Data("dev-snapshot: wrote \(url.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("dev-snapshot: \(error)\n".utf8))
        }
    }
}
