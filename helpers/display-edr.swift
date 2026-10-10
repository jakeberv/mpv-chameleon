// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 mpv-chameleon contributors
import AppKit
import Foundation

@main
struct ChameleonDisplayHelper {
    static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data("mpv-chameleon: \(message)\n".utf8))
        exit(code)
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var requested: String?
        if arguments == ["--help"] {
            print("Usage: mpv-chameleon [--display MPV_DISPLAY_NAME | --version | --help]")
            return
        } else if arguments == ["--version"] {
            print("mpv-chameleon 0.1.0 (schema 1)")
            return
        } else if arguments.count == 2 && arguments[0] == "--display" {
            requested = arguments[1]
        } else if !arguments.isEmpty {
            fail("invalid arguments; use --help", code: 64)
        }
        guard #available(macOS 10.15, *) else {
            fail("macOS 10.15 or newer is required", code: 69)
        }
        // NSScreen must be queried on the main thread in a GUI login session.
        // Each invocation obtains a fresh list, so there is no persistent cache.
        let screens = NSScreen.screens
        let records = screens.compactMap { screen -> DisplayRecord? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  number.uint32Value != 0 else { return nil }
            let id = number.uint32Value
            let rect = screen.frame
            return DisplayRecord(id: id, name: screen.localizedName,
                serial: CGDisplaySerialNumber(id),
                potential: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
                current: Double(screen.maximumExtendedDynamicRangeColorComponentValue),
                reference: Double(screen.maximumReferenceExtendedDynamicRangeColorComponentValue),
                x: Double(rect.origin.x), y: Double(rect.origin.y),
                width: Double(rect.width), height: Double(rect.height))
        }
        do {
            let data = try encodeResponse(displays: records, requested: requested)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        } catch {
            fail("unable to encode display capabilities", code: 70)
        }
    }
}
