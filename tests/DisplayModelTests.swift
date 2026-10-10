// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 mpv-chameleon contributors
import Foundation

@main
struct DisplayModelTests {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            count += 1
        }
        func display(_ id: UInt32, _ name: String, _ serial: UInt32, _ potential: Double) -> DisplayRecord {
            DisplayRecord(id: id, name: name, serial: serial, potential: potential,
                          current: 1, reference: 0, x: 0, y: 0, width: 1920, height: 1080)
        }
        let hdr = display(7, "Panel", 12345, 16)
        let sdr = display(8, "Panel", 54321, 1)
        check(hdr.hdrCapable, "potential > 1 is capable even if current is 1")
        check(!sdr.hdrCapable, "1 is SDR")
        for invalid in [Double.nan, Double.infinity, -1, 0, 0.9] {
            check(!display(9, "Bad", 0, invalid).hdrCapable, "invalid is conservative")
        }
        check(selectDisplay("Panel (12345)", from: [hdr, sdr]).displayID == 7, "match serial, not display ID")
        check(selectDisplay("Panel (7)", from: [hdr, sdr]).status == "unknown", "never substitute ID for serial")
        check(selectDisplay("Panel", from: [hdr, sdr]).status == "ambiguous", "duplicate names")
        check(selectDisplay("Panel", from: [hdr]).status == "name", "unique bare name")
        check(selectDisplay("Panel (999)", from: [hdr]).status == "unknown", "stale serial must not fall back")
        check(selectDisplay("Missing", from: [hdr]).status == "unknown", "unknown name")
        check(selectDisplay("", from: []).status == "unknown", "empty list")
        check(selectDisplay("Panel (0)", from: [display(1, "Panel", 0, 16), display(2, "Panel", 0, 1)]).status == "ambiguous", "zero serial collision")
        check(selectDisplay("Panel (42)", from: [display(3, "Panel (12)", 42, 2)]).displayID == 3, "numeric name suffix normalized")
        check(selectDisplay("画面 🦎 (4)", from: [display(4, "画面 🦎", 4, 2)]).displayID == 4, "unicode")
        let escaped = display(5, "A\"\tB\nC\\D", 777777, 1)
        let data = try encodeResponse(displays: [escaped, display(6, "Invalid", 0, .nan)], requested: nil)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let records = json["displays"] as! [[String: Any]]
        check(json["schema_version"] as? Int == 1, "schema")
        check(records[0]["name"] as? String == escaped.name, "JSON escapes names")
        check(records[0]["potential_edr"] as? Double == 1, "numeric EDR")
        check(records[1]["potential_edr"] is NSNull, "invalid encoded null")
        check(!String(decoding: data, as: UTF8.self).contains("777777"), "serial not exposed")
        let selected = try JSONSerialization.jsonObject(with: encodeResponse(displays: [hdr], requested: "Panel (12345)")) as! [String: Any]
        check((selected["selection"] as? [String: Any])?["display_id"] as? Int == 7, "selected ID serializes")
        let empty = try JSONSerialization.jsonObject(with: encodeResponse(displays: [], requested: "Missing")) as! [String: Any]
        check((empty["displays"] as? [Any])?.isEmpty == true, "no displays is valid JSON")
        print("Swift: \(count) assertions passed")
    }
}
