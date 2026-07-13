import Foundation

/// How a held pad's chord actually unfolds in time — the piece Orchid's
/// manual calls "performance modes" (it ships 5: Arp/Strum/Slop/Pattern/Harp;
/// Chordscape covers the first 3, the ones that don't need a preset-pattern
/// library or a harp-glissando voice-stealing scheme to feel worthwhile).
enum PerformanceMode: Int, CaseIterable, Identifiable, PickerOption, Codable {
    case sustain, arp, strum, slop

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sustain: return "Sustain"
        case .arp: return "Arp"
        case .strum: return "Strum"
        case .slop: return "Slop"
        }
    }

    var icon: String {
        switch self {
        case .sustain: return "square.stack"
        case .arp: return "arrow.triangle.branch"
        case .strum: return "hand.draw"
        case .slop: return "shuffle"
        }
    }
}
