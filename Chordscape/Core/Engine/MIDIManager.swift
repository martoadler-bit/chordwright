import CoreMIDI
import Foundation

/// Listens to every available Core MIDI source (USB, Bluetooth, virtual) and
/// forwards Note On/Off to `ChordscapeViewModel`, which snaps each incoming
/// pitch to the nearest of the 7 on-screen pads and plays it exactly like a
/// tap — same chord generation, same voicing, same performance mode as
/// touching the screen. No MIDI Learn, no CC/pitch bend, no velocity — just
/// notes, mirroring Modula's `MIDIManager` (same Core MIDI setup, same
/// packet-parsing gotcha documented below).
@MainActor
final class MIDIManager: ObservableObject {
    @Published private(set) var connectedSourceNames: [String] = []

    private weak var viewModel: ChordscapeViewModel?
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    init(viewModel: ChordscapeViewModel) {
        self.viewModel = viewModel
        setUpCoreMIDI()
    }

    private func setUpCoreMIDI() {
        let clientStatus = MIDIClientCreateWithBlock("ChordscapeMIDIClient" as CFString, &client) { [weak self] _ in
            Task { @MainActor in
                self?.connectAllSources()
            }
        }
        guard clientStatus == noErr else { return }

        let portStatus = MIDIInputPortCreateWithBlock(client, "ChordscapeInputPort" as CFString, &inputPort) { [weak self] packetList, _ in
            let bytes = MIDIManager.bytes(from: packetList)
            Task { @MainActor in
                self?.handle(bytes: bytes)
            }
        }
        guard portStatus == noErr else { return }

        connectAllSources()
    }

    private func connectAllSources() {
        let sourceCount = MIDIGetNumberOfSources()
        var names: [String] = []
        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(inputPort, source, nil)
            if let name = Self.name(of: source), !Self.isPhantomSession(name) {
                names.append(name)
            }
        }
        connectedSourceNames = names
    }

    /// iOS always exposes a built-in "Network Session 1" RTP-MIDI endpoint
    /// as a source, whether or not anything is actually connected to it —
    /// showing it in the header's "connected controller" pill reads as a
    /// real MIDI device being plugged in when nothing is. Still connected
    /// (harmless, and it's the only way to receive over actual Network MIDI
    /// if the user does set one up), just excluded from the display list.
    private static func isPhantomSession(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("network session")
    }

    private static func name(of endpoint: MIDIEndpointRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &unmanagedName)
        guard status == noErr, let cfName = unmanagedName?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    /// Walks the packet list via a pointer into the list's own buffer rather
    /// than copying each packet into a local variable first — `MIDIPacketNext`
    /// computes the next packet's address from wherever you hand it, so
    /// stepping from a stack copy (a common copy-pasted mistake) silently
    /// breaks on any packet list with more than one packet in it.
    private nonisolated static func bytes(from packetList: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        withUnsafePointer(to: packetList.pointee.packet) { firstPacket in
            var packetPointer = firstPacket
            for _ in 0..<packetList.pointee.numPackets {
                let packet = packetPointer.pointee
                let byteCount = Int(packet.length)
                let bytes = withUnsafeBytes(of: packet.data) { raw -> [UInt8] in
                    Array(raw.prefix(byteCount))
                }
                messages.append(bytes)
                packetPointer = UnsafePointer(MIDIPacketNext(packetPointer))
            }
        }
        return messages
    }

    private func handle(bytes messages: [[UInt8]]) {
        for bytes in messages {
            guard bytes.count >= 3 else { continue }
            let status = bytes[0] & 0xF0
            let note = Int(bytes[1])
            let velocity = Int(bytes[2])

            if status == 0x90 && velocity > 0 {
                viewModel?.externalNoteOn(note)
            } else if status == 0x80 || (status == 0x90 && velocity == 0) {
                viewModel?.externalNoteOff(note)
            }
        }
    }
}
