import Foundation

/// Which knob the drag-up-from-a-pad gesture sweeps while held. Filter is
/// the default (and the only option before this was added) — a classic
/// mod-wheel-to-filter routing; the others reuse the exact same 0...1
/// "amount" computed from the drag, just applied to a different engine
/// setter.
enum ModulationTarget: String, CaseIterable, Identifiable, Codable, PickerOption {
    case filter = "Filter", ambience = "Ambience", decay = "Decay", bass = "Bass"

    var id: String { rawValue }
    var label: String { rawValue }
    var icon: String {
        switch self {
        case .filter: "slider.horizontal.3"
        case .ambience: "waveform.path"
        case .decay: "waveform.path.ecg"
        case .bass: "waveform.path.badge.minus"
        }
    }
}
