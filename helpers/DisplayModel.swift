// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 mpv-chameleon contributors
import Foundation

struct DisplayRecord: Encodable {
    let id: UInt32
    let name: String
    // Used only for matching mpv's local identifier; never serialized.
    let serial: UInt32
    let potential: Double
    let current: Double
    let reference: Double
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var hdrCapable: Bool { potential.isFinite && potential > 1 }
    var matchingName: String {
        name.replacingOccurrences(of: #" \([0-9]+\)$"#, with: "", options: .regularExpression)
    }
    var mpvName: String { "\(matchingName) (\(serial))" }

    enum CodingKeys: String, CodingKey {
        case id, name, frame
        case potential = "potential_edr", current = "current_edr"
        case reference = "reference_edr", hdrCapable = "hdr_capable"
    }
    func encode(to encoder: Encoder) throws {
        var out = encoder.container(keyedBy: CodingKeys.self)
        try out.encode(id, forKey: .id)
        try out.encode(name, forKey: .name)
        try out.encode(hdrCapable, forKey: .hdrCapable)
        // Treat missing/invalid hardware values as unknown, not JSON NaN/Infinity.
        for (key, value, minimum) in [(CodingKeys.potential, potential, 1.0),
                                       (.current, current, 1.0), (.reference, reference, 0.0)] {
            if value.isFinite && value >= minimum { try out.encode(value, forKey: key) }
            else { try out.encodeNil(forKey: key) }
        }
        let geometry = ["x": x, "y": y, "width": width, "height": height]
        if geometry.values.allSatisfy({ $0.isFinite }) {
            try out.encode(geometry, forKey: .frame)
        } else { try out.encodeNil(forKey: .frame) }
    }
}

struct DisplaySelection: Encodable {
    let status: String
    let displayID: UInt32?
    enum CodingKeys: String, CodingKey { case status; case displayID = "display_id" }
}

func selectDisplay(_ requested: String, from displays: [DisplayRecord]) -> DisplaySelection {
    let exact = displays.filter { $0.mpvName == requested }
    if exact.count == 1 { return DisplaySelection(status: "exact", displayID: exact[0].id) }
    if exact.count > 1 { return DisplaySelection(status: "ambiguous", displayID: nil) }
    // A supplied serial that no longer matches could indicate a disconnected
    // monitor. Never throw away that evidence and guess using only its model.
    if requested.range(of: #" \([0-9]+\)$"#, options: .regularExpression) != nil {
        return DisplaySelection(status: "unknown", displayID: nil)
    }
    let byName = displays.filter { $0.name == requested || $0.matchingName == requested }
    if byName.count == 1 { return DisplaySelection(status: "name", displayID: byName[0].id) }
    return DisplaySelection(status: byName.isEmpty ? "unknown" : "ambiguous", displayID: nil)
}

func encodeResponse(displays: [DisplayRecord], requested: String?) throws -> Data {
    struct Response: Encodable {
        let schema_version = 1
        let displays: [DisplayRecord]
        let selection: DisplaySelection?
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(Response(displays: displays,
        selection: requested.map { selectDisplay($0, from: displays) }))
}
