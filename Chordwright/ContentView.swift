import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ChordwrightViewModel
    @ObservedObject private var engine: ChordwrightAudioEngine
    @StateObject private var midiManager: MIDIManager

    @State private var showingPatches = false
    @State private var showingHelp = false
    /// One glow position per active touch, keyed by drag-origin pad — same
    /// per-touch keying pattern the view model already uses for glissando
    /// tracking, so two fingers each get their own glow instead of
    /// clobbering a single shared position.
    @State private var glowPoints: [Int: CGPoint] = [:]
    /// Persisted across launches (`@AppStorage`) since it's a UI preference,
    /// not instrument state — doesn't belong in a `Patch`. Every color in
    /// `Colors.swift` is dynamic, so flipping this is the only code needed
    /// to re-skin the whole app.
    @AppStorage("chordwright.isDarkMode") private var isDarkMode = false

    init() {
        let vm = ChordwrightViewModel()
        _viewModel = StateObject(wrappedValue: vm)
        _engine = ObservedObject(wrappedValue: vm.engine)
        _midiManager = StateObject(wrappedValue: MIDIManager(viewModel: vm))
    }

    private let padColors: [Color] = [
        .chordwrightCoral, .chordwrightGold, .chordwrightMoss, .chordwrightMint, .chordwrightSky, .chordwrightLavender, .chordwrightBlush
    ]

    var body: some View {
        ZStack {
            Color.chordwrightBackground.ignoresSafeArea()
            // A GeometryReader around the ScrollView, plus `minHeight` on
            // the inner VStack, is the standard trick to let the layout
            // absorb whatever vertical space the fixed-size controls above
            // don't use — instead of the fixed magic-number pad-row heights
            // from earlier passes, which kept guessing wrong (too tall →
            // scroll, too short → leftover empty space at the bottom).
            // `ScrollView` stays as a pure safety net for screens too short
            // to fit everything even at the pad row's minimum height.
            //
            // The pad row itself is capped (not `maxHeight: .infinity`
            // anymore) — on iPad especially, "soak up all remaining space"
            // meant genuinely huge keys, which the user flagged as too
            // long/tall on both iPad and iPhone. The leftover space below
            // it used to just sit empty ("queda espacio sin nada abajo");
            // the `Spacer()` before `transportRow` pushes it down to the
            // bottom of the screen instead. That single Spacer is enough on
            // iPhone (either orientation) and iPad landscape, but iPad
            // portrait is tall enough that pushing ALL the leftover space
            // into one gap still reads as "a lot of empty space in the
            // middle" even though it's technically being used — spreading
            // that same leftover space across a few gaps instead (one more
            // above the knobs, one more above the pads) reads as generous
            // breathing room rather than emptiness.
            GeometryReader { outerGeo in
                // iPad portrait only: both `UIUserInterfaceSizeClass`es
                // report `.regular` on iPad in *either* orientation, so
                // there's no way to isolate "iPad, but only portrait" via
                // size classes — actual measured width/height is what
                // distinguishes the orientations. iPhone (either rotation)
                // never exceeds ~930pt on its long edge, so a >500pt width
                // combined with portrait aspect (height > width) uniquely
                // picks out iPad portrait without touching iPhone or iPad
                // landscape.
                let isIPadPortrait = outerGeo.size.width > 500 && outerGeo.size.height > outerGeo.size.width
                ScrollView {
                    VStack(spacing: 10) {
                        header
                        screen
                        RootScalePickerView(rootPitchClass: $viewModel.rootPitchClass, scale: $viewModel.scale, keyModeOn: $viewModel.keyModeOn)
                        if !viewModel.keyModeOn {
                            SegmentedIconPicker(selection: $viewModel.chordQuality)
                        }
                        MultiSegmentedIconPicker(selection: viewModel.activeEngines, toggle: viewModel.toggleEngine)
                        SegmentedIconPicker(selection: $viewModel.performanceMode)
                        SegmentedIconPicker(selection: $viewModel.modulationTarget)
                        if isIPadPortrait { Spacer(minLength: 0) }
                        knobRow
                        if isIPadPortrait { Spacer(minLength: 0) }
                        padRow
                            .frame(minHeight: 64, maxHeight: 78)
                        Spacer(minLength: 0)
                        transportRow
                    }
                    .padding(16)
                    .frame(minHeight: outerGeo.size.height)
                }
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear { viewModel.start() }
        .sheet(isPresented: $showingPatches) {
            PatchBrowserView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
    }

    /// Root/scale/key-mode/quality/engine/performance-mode live back on the
    /// main screen (were briefly moved into a Settings sheet, then user
    /// asked for that reverted — only Patches and the Guide stay as their
    /// own sheets).
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chordwright")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.chordwrightInk)
                // Previously just plain text under the title — read as a
                // label, not a button, so the user reported not realizing
                // it opened Patches at all. Now a filled pill with an icon,
                // same visual language as the Key On/Off pill, so it
                // unmistakably reads as tappable.
                Button {
                    showingPatches = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(viewModel.currentPatchName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.chordwrightPanel))
                    .foregroundStyle(Color.chordwrightInk)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if let name = midiManager.connectedSourceNames.first {
                HStack(spacing: 4) {
                    Image(systemName: "pianokeys")
                    Text(name)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.chordwrightPanel))
                .foregroundStyle(Color.chordwrightInk)
            }
            Button {
                showingHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.chordwrightInk.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Guide")
            Button {
                isDarkMode.toggle()
            } label: {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.chordwrightInk.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle dark mode")
            Button {
                viewModel.panicStopAll()
            } label: {
                Image(systemName: "stop.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.chordwrightInk.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop all sound")
        }
    }

    private var screen: some View {
        VStack(spacing: 7) {
            Text(engine.currentChordLabel)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.chordwrightInk)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            StepDotsView(
                stepHasContent: engine.stepHasContent,
                currentStep: engine.currentStep,
                isPlaying: engine.isLoopPlaying
            )
            .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.chordwrightPanel))
    }

    /// A 4-column grid — Bass and Tempo used to sit off in the transport
    /// row, oddly separated from the other 6 knobs; the user asked for all
    /// 8 to read as one instrument-wide control bank ("que estén con las
    /// otras, 4 por fila"). 4×2 fits every knob in exactly the same 2 rows
    /// the old 3×2-of-6 layout used, so this is a pure reorganization, not
    /// added height.
    private var knobRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
            ChordwrightKnob(
                label: "Complexity", value: viewModel.complexity, range: 0...1, defaultValue: 0.4,
                valueText: { String(format: "%.0f%%", $0 * 100) }
            ) { viewModel.complexity = $0 }
            ChordwrightKnob(
                label: "Voicing", value: viewModel.voicingSteps, range: -6...6, defaultValue: 0,
                valueText: { $0 == 0 ? "Root" : String(format: "%+.0f", $0) }
            ) { viewModel.voicingSteps = $0.rounded() }
            ChordwrightKnob(
                label: "Tone", value: viewModel.tone, range: 300...6_000, defaultValue: 2_400,
                valueText: { $0 >= 1_000 ? String(format: "%.1fk", $0 / 1_000) : String(format: "%.0f", $0) }
            ) { viewModel.tone = $0 }
            ChordwrightKnob(
                label: "Decay", value: viewModel.decayKnob, range: 0...1, defaultValue: 0.35,
                valueText: { String(format: "%.0f%%", $0 * 100) }
            ) { viewModel.decayKnob = $0 }
            ChordwrightKnob(
                label: "Ambience", value: viewModel.ambience, range: 0...1, defaultValue: 0.3,
                valueText: { String(format: "%.0f%%", $0 * 100) }
            ) { viewModel.ambience = $0 }
            ChordwrightKnob(
                label: "Glide", value: viewModel.glideTime, range: 0...0.5, defaultValue: 0.15,
                valueText: { String(format: "%.2fs", $0) }
            ) { viewModel.glideTime = $0 }
            ChordwrightKnob(
                label: "Bass", value: viewModel.bassLevel, range: 0...1, defaultValue: 0.5,
                valueText: { String(format: "%.0f%%", $0 * 100) }
            ) { viewModel.bassLevel = $0 }
            ChordwrightKnob(
                label: "Tempo", value: viewModel.tempo, range: 60...160, defaultValue: 100,
                valueText: { String(format: "%.0f", $0) }
            ) { viewModel.tempo = $0 }
        }
    }

    /// One `DragGesture` per pad, each reporting its OWN translation — not a
    /// single shared gesture over the whole row. SwiftUI keeps delivering a
    /// touch's updates to whichever pad captured it even once the finger has
    /// visually moved past that pad's bounds, so this is enough to detect a
    /// glissando (drag into a neighbor) while still letting two different
    /// fingers hold two different pads independently (each keeps its own
    /// gesture instance). The pad's own view stays purely presentational —
    /// see `PadView`. The SAME drag's vertical component (`translation.height`)
    /// drives the filter-mod gesture — dragging up from a held pad brightens
    /// the sound — so a diagonal drag glides across pads and modulates at once.
    ///
    /// The glow's position is computed from that same `translation` plus
    /// pad `i`'s own known starting center (`geo` is shared by the gesture
    /// and the glow overlay since both live inside the SAME `GeometryReader`)
    /// rather than via `drag.location` in a separately-named coordinate
    /// space read from a `ZStack` sibling — that version never actually
    /// rendered the glow, a named-coordinate-space handshake across a
    /// `GeometryReader`/`ZStack`-sibling boundary is a notoriously fragile
    /// SwiftUI pattern. This is an approximation (assumes the touch started
    /// near the pad's center, not wherever it actually landed), but for a
    /// decorative glow that's a fine trade for something that reliably shows up.
    /// Height is set at the call site (`body`'s `.frame(minHeight:maxHeight:)`)
    /// to a fairly short, capped range — keys were reported as too tall on
    /// both iPhone and (especially, since it had much more vertical room to
    /// "soak up") iPad, so this stays capped rather than growing to fill
    /// leftover space; a trailing `Spacer()` there absorbs any extra room
    /// on tall screens instead.
    private var padRow: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let padWidth = (geo.size.width - spacing * CGFloat(ChordwrightViewModel.degreeCount - 1)) / CGFloat(ChordwrightViewModel.degreeCount)
            ZStack {
                HStack(spacing: spacing) {
                    ForEach(0..<ChordwrightViewModel.degreeCount, id: \.self) { i in
                        PadView(
                            label: viewModel.degreeName(i),
                            color: padColors[i % padColors.count],
                            isActive: viewModel.activePads.contains(i)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    viewModel.glissandoChanged(originPad: i, translationX: drag.translation.width, translationY: drag.translation.height, padWidth: padWidth)
                                    let padCenterX = CGFloat(i) * (padWidth + spacing) + padWidth / 2
                                    let padCenterY = geo.size.height / 2
                                    glowPoints[i] = CGPoint(x: padCenterX + drag.translation.width, y: padCenterY + drag.translation.height)
                                }
                                .onEnded { _ in
                                    viewModel.glissandoEnded(originPad: i)
                                    glowPoints.removeValue(forKey: i)
                                }
                        )
                    }
                }

                ForEach(Array(glowPoints.keys), id: \.self) { origin in
                    if let point = glowPoints[origin] {
                        GlowView(color: padColors[origin % padColors.count], intensity: viewModel.modulationAmount)
                            .position(point)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    /// Bass and Tempo moved into `knobRow` (see above), so this row is now
    /// just the 3 transport buttons — spread evenly across the full width
    /// instead of left-pinned-with-trailing-spacer, since there's no longer
    /// a knob cluster on the right to balance against.
    private var transportRow: some View {
        HStack {
            Spacer()
            transportButton(icon: engine.isLoopPlaying ? "pause.fill" : "play.fill", active: engine.isLoopPlaying) {
                engine.togglePlay()
            }
            Spacer()
            transportButton(icon: "circle.fill", active: engine.isRecording, activeColor: .red) {
                engine.toggleRecording()
            }
            Spacer()
            transportButton(icon: "trash", active: false) {
                engine.clearLoop()
            }
            Spacer()
        }
    }

    private func transportButton(icon: String, active: Bool, activeColor: Color = .chordwrightCoral, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Circle().fill(active ? activeColor : Color.chordwrightPanel))
                .foregroundStyle(active ? Color.white : Color.chordwrightInk)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
