import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var model: FlowDoModel
    @State private var checkpoint = ""
    @State private var unit: CheckpointUnit = .minutes
    @State private var checkpointError: String?
    @State private var idleGrace = "60"
    @State private var idleError: String?
    @State private var bpm = "70"
    @State private var pulseError: String?
    @State private var collecting = false
    @State private var sampler = PulseTapSampler()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackgroundMusicPreferences(music: model.music)
            Divider()
            Toggle("Show task badge", isOn: Binding(
                get: { model.badgeVisible }, set: { if $0 { model.showBadge() } else { model.hideBadge() } }))
                .disabled(model.currentTask == nil)
            Picker("Badge position", selection: Binding(
                get: { model.badgePosition }, set: { model.setBadgePosition($0) })) {
                ForEach(BadgePosition.allCases) { position in Text(position.label).tag(position) }
            }
            Divider()
            HStack {
                Text("Idle grace")
                TextField("60", text: $idleGrace).textFieldStyle(.roundedBorder).frame(width: 65)
                Text("seconds")
            }
            Button("Save idle grace") {
                guard let seconds = Int(idleGrace.trimmingCharacters(in: .whitespacesAndNewlines)), (1...3600).contains(seconds) else {
                    idleError = "Enter 1 to 3600 seconds."
                    return
                }
                model.setIdleGrace(seconds: seconds)
                idleError = nil
            }
            if let error = idleError { Text(error).font(.caption) }
            Text("Each idle interval steps back: green → yellow → red → dimmed break. Timers freeze after the first interval; activity resumes them. Saving starts a new session; total time is kept.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Pulse", isOn: Binding(get: { model.pulseEnabled }, set: { model.setPulseEnabled($0) }))
            HStack {
                TextField("70", text: $bpm).textFieldStyle(.roundedBorder).frame(width: 65)
                Text("BPM")
                Button("Set BPM") { saveBPM() }
            }
            Text("Pulse pauses with FlowDo and respects Reduce Motion.").font(.caption).foregroundStyle(.secondary)
            Button("Collect Pulse") {
                sampler = PulseTapSampler()
                pulseError = nil
                collecting = true
            }
            if collecting {
                Text("Tap the spacebar in time with your pulse at least 5 times")
                    .font(.callout)
                SpaceTapCapture {
                    sampler.record(at: ProcessInfo.processInfo.systemUptime)
                } onCancel: { collecting = false; sampler = PulseTapSampler() }
                .frame(height: 24)
                .background(Color.secondary.opacity(0.1))
                .overlay(Text("Listening for Space…").font(.caption).allowsHitTesting(false))
                Text("\(sampler.tapCount) taps" + (sampler.bpm.map { " · \(String(format: "%.1f", $0)) BPM" } ?? ""))
                    .font(.caption).monospacedDigit()
                HStack {
                    Button("Use collected BPM") {
                        guard let measured = sampler.bpm, PulseRhythm.supportedBPM.contains(measured) else { return }
                        model.setPulse(bpm: measured)
                        bpm = String(format: "%.1f", model.pulseBPM)
                        collecting = false
                        sampler = PulseTapSampler()
                    }.disabled(sampler.bpm.map { !PulseRhythm.supportedBPM.contains($0) } ?? true)
                    Button("Cancel") { collecting = false; sampler = PulseTapSampler() }
                }
                Text("Uses the average interval between your last five presses. Keep tapping to refine it. Supported range: 30–180 BPM.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = pulseError { Text(error).font(.caption) }
            Divider()
            HStack {
                Text("Pink checkpoint every")
                TextField("20", text: $checkpoint).textFieldStyle(.roundedBorder).frame(width: 65)
                    .onSubmit { saveCheckpoint() }
            }
            Picker("Interval unit", selection: $unit) {
                ForEach(CheckpointUnit.allCases) { unit in Text(unit.rawValue.capitalized).tag(unit) }
            }.pickerStyle(.radioGroup)
            Button("Save checkpoint interval", action: saveCheckpoint)
            if let error = checkpointError { Text(error).font(.caption) }
            Text("Repeats during each engagement session. Blank or 0 turns checkpoints off. Saving starts a new session; total time is kept.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Log activity locally", isOn: Binding(
                get: { model.loggingEnabled }, set: { model.setLoggingEnabled($0) }))
            Text("Off by default. Logs task names, task and engagement start/stop boundaries, durations, and achievements. No raw input. Turning off keeps existing files.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.loggingError { Text(error).font(.caption) }
            Button("Open log folder") { model.openLogFolder() }
            Divider()
            Toggle("Fast thresholds for testing", isOn: Binding(
                get: { model.debugThresholds }, set: { model.setDebugThresholds($0) }))
            Text(model.debugThresholds ? "Green after 20s · Your idle grace still applies"
                 : "Green after 4m · Your idle grace still applies")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear { collecting = false; sampler = PulseTapSampler() }
        .onAppear {
            checkpoint = String(model.checkpointValue)
            unit = model.checkpointUnit
            idleGrace = String(model.idleGraceSeconds)
            bpm = String(format: "%.1f", model.pulseBPM)
        }
    }

    private func saveBPM() {
        guard let value = Double(bpm.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite, PulseRhythm.supportedBPM.contains(value) else {
            pulseError = "Enter a BPM from 30 to 180."
            return
        }
        model.setPulse(bpm: value)
        pulseError = nil
    }

    private func saveCheckpoint() {
        let value = checkpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(value.isEmpty ? "0" : value), (0...86_400).contains(number) else {
            checkpointError = "Enter a whole number from 0 to 86400."
            return
        }
        model.setCheckpoint(value: number, unit: unit)
        checkpoint = String(model.checkpointValue)
        checkpointError = nil
    }
}

private struct BackgroundMusicPreferences: View {
    @ObservedObject var music: BackgroundMusic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background music").font(.headline)
            Button(music.importing ? "Importing…" : "Choose MP3…") { music.chooseMP3() }
                .disabled(music.importing)
            if let name = music.trackName {
                Text(name).font(.caption).lineLimit(2).help(name)
                Toggle("Play music", isOn: Binding(get: { music.enabled }, set: { music.setEnabled($0) }))
                HStack {
                    Text("Volume")
                    Slider(value: Binding(get: { music.volume }, set: { music.setVolume($0) }), in: 0...1)
                        .accessibilityLabel("Music volume")
                    Text("\(Int(music.volume * 100))% ").monospacedDigit()
                }
                Button("Remove MP3") { music.removeTrack() }.disabled(music.importing)
            }
            if let error = music.errorMessage { Text(error).font(.caption) }
            Text("Loops locally, including between tasks. Pause FlowDo pauses music; Resume continues it. The track and volume are remembered.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// First-responder-only capture: never monitors other apps or installs a global tap.
private struct SpaceTapCapture: NSViewRepresentable {
    var onTap: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> SpaceTapView {
        let view = SpaceTapView()
        view.onTap = onTap
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: SpaceTapView, context: Context) {
        view.onTap = onTap
        view.onCancel = onCancel
    }
}

private final class SpaceTapView: NSView {
    var onTap: (() -> Void)?
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        if event.keyCode == 49 {
            guard !event.isARepeat,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return }
            onTap?()
        } else { super.keyDown(with: event) }
    }
}
