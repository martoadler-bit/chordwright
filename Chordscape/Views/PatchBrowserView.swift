import SwiftUI

/// Browse/save/load patches — factory presets (one per engine, a quick tour
/// of the 6 timbres) plus whatever the user has saved. Tapping a row loads
/// it and dismisses; only user patches can be deleted.
struct PatchBrowserView: View {
    @ObservedObject var viewModel: ChordscapeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newPatchName: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    saveRow

                    sectionLabel("Factory")
                    ForEach(FactoryPatches.all) { patch in
                        patchRow(patch, deletable: false)
                    }

                    if !viewModel.userPatches.isEmpty {
                        sectionLabel("My Patches")
                        ForEach(viewModel.userPatches) { patch in
                            patchRow(patch, deletable: true)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.chordscapeBackground.ignoresSafeArea())
            .navigationTitle("Patches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var saveRow: some View {
        HStack(spacing: 10) {
            TextField("Patch name", text: $newPatchName)
                .font(.system(size: 14, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.chordscapePanel))
            Button {
                let trimmed = newPatchName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                viewModel.saveCurrentPatch(as: trimmed)
                newPatchName = ""
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.chordscapeCoral))
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.chordscapeInk.opacity(0.5))
    }

    private func patchRow(_ patch: Patch, deletable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(patch.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.chordscapeInk)
                Text("\(patch.activeEngines.map(\.label).sorted().joined(separator: "+")) · \(patch.scale.rawValue) · \(patch.performanceMode.label)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.chordscapeInk.opacity(0.5))
            }
            Spacer()
            if patch.name == viewModel.currentPatchName {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.chordscapeCoral)
            }
            if deletable {
                Button {
                    viewModel.deletePatch(patch)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.chordscapeInk.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.chordscapePanel))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            viewModel.loadPatch(patch)
            dismiss()
        }
    }
}
