import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusItemController: NSObject {
    let model: FlowDoModel
    private let item = NSStatusBar.system.statusItem(withLength: 28)
    private let popover = NSPopover()
    private var badge: TaskBadgeController?

    init(model: FlowDoModel) {
        self.model = model
        super.init()
        badge = TaskBadgeController(model: model)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuPopover(model: model))
        if let button = item.button {
            let orb = PassiveHostingView(rootView: OrbView(model: model))
            orb.frame = button.bounds
            orb.autoresizingMask = [.width, .height]
            button.addSubview(orb)
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("FlowDo")
            button.toolTip = "FlowDo — one intention at a time"
        }
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A local, nonactivating overlay; no Notification Center permission or history.
@MainActor
private final class TaskBadgeController: NSObject {
    private let model: FlowDoModel
    private let panel: NSPanel
    private var subscription: AnyCancellable?

    init(model: FlowDoModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0.5
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: TaskBadgeView(model: model))
        subscription = model.$currentTask.combineLatest(model.$badgeVisible, model.$badgePosition)
            .receive(on: RunLoop.main)
            .sink { [weak self] task, visible, _ in
                guard let self else { return }
                if task != nil && visible {
                    self.positionBadge()
                    self.panel.orderFrontRegardless()
                } else { self.panel.orderOut(nil) }
            }
        NotificationCenter.default.addObserver(self, selector: #selector(positionBadge),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func positionBadge() {
        // The primary display is stable even when another app changes key window.
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let left = model.badgePosition == .topLeft || model.badgePosition == .bottomLeft
        let top = model.badgePosition == .topLeft || model.badgePosition == .topRight
        let x = left ? frame.minX + 16 : frame.maxX - panel.frame.width - 16
        let y = top ? frame.maxY - 16 : frame.minY + panel.frame.height + 16
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }
}

private struct TaskBadgeView: View {
    @ObservedObject var model: FlowDoModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                OrbView(model: model, animationsEnabled: model.badgeVisible)
                Text(model.currentTask?.title ?? "").font(.callout)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button { model.hideBadge() } label: {
                    Image(systemName: "xmark").font(.caption).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Hide task badge")
                .accessibilityLabel("Hide task badge")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Session Time / Total Time on Task:")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(FlowDoModel.formattedTime(model.sessionTime)) / \(FlowDoModel.formattedTime(model.totalTaskTime))")
                    .font(.system(.callout, design: .monospaced)).monospacedDigit()
            }
        }
        .padding(12)
        .frame(width: 360, height: 120)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.15)))
    }
}
