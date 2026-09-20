import SwiftUI

struct MenuPopover: View {
    @ObservedObject var model: FlowDoModel
    @State private var title = ""
    @State private var editing = false
    @State private var preferences = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("FlowDo").font(.headline)
                    Spacer()
                    if model.paused { Text("Paused").foregroundStyle(.secondary) }
                }
                if let message = model.errorMessage {
                    Text(message).font(.callout).textSelection(.enabled)
                    if !model.ready {
                        Button("Retry loading") { Task { await model.restore() } }
                            .disabled(model.busy)
                    }
                }
                if model.ready {
                    if let task = model.currentTask, !editing {
                        Text(task.title).font(.title3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button(model.badgeVisible ? "Hide task badge" : "Show task badge") {
                            if model.badgeVisible { model.hideBadge() } else { model.showBadge() }
                        }
                        Text(model.paused ? "Take your time." :
                             (model.countersIdle ? "Idle — timers paused" : "Current state: \(model.state.label)"))
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Task Complete!") { Task { await model.complete() } }
                            Button("Change") { title = task.title; editing = true; titleFocused = true }
                        }.disabled(model.busy)
                    } else {
                        if model.completionStartedAt != nil {
                            HStack {
                                OrbView(model: model, diameter: 32)
                                Text("Task complete!").font(.headline)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("What are you working on?")
                        TextField("One current task", text: $title)
                            .textFieldStyle(.roundedBorder).focused($titleFocused)
                            .onSubmit { save() }
                        HStack {
                            Button(editing ? "Save" : "Start", action: save)
                                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                            if editing { Button("Cancel") { editing = false } }
                        }
                    }
                } else if model.busy { ProgressView().controlSize(.small) }
                Divider()
                Button(model.paused ? "Resume FlowDo" : "Pause FlowDo") { model.togglePause() }
                Button("Preferences…") { preferences.toggle() }
                if preferences { PreferencesView(model: model) }
                Button("Quit FlowDo") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .disabled(model.busy)
            }
            .padding(20)
        }
        .frame(width: 360, height: preferences ? 580 : 340)
        .onAppear { titleFocused = model.currentTask == nil }
        .onChange(of: model.currentTask?.id) { id in
            if id == nil {
                title = ""
                editing = false
                titleFocused = true
            }
        }
    }

    private func save() {
        Task {
            await model.save(title: title)
            if model.errorMessage == nil && model.currentTask != nil {
                editing = false
                title = ""
            }
        }
    }
}
