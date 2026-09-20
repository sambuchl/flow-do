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
    private var positionedCorner: BadgePosition?
    private var resizeStartFrame: NSRect?

    init(model: FlowDoModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0.5
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 180, height: 160)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = BadgeHostingView(rootView: TaskBadgeView(model: model,
            resize: { [weak self] translation in self?.resizeBadge(translation) },
            endResize: { [weak self] in self?.resizeStartFrame = nil }))
        subscription = model.$currentTask.combineLatest(model.$badgeVisible, model.$badgePosition)
            .receive(on: RunLoop.main)
            .sink { [weak self] task, visible, _ in
                guard let self else { return }
                if task != nil && visible {
                    // Task edits and showing the badge must preserve a dragged position.
                    if self.positionedCorner != self.model.badgePosition { self.positionBadge() }
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
        positionedCorner = model.badgePosition
    }

    private func resizeBadge(_ translation: CGSize) {
        if resizeStartFrame == nil { resizeStartFrame = panel.frame }
        guard let start = resizeStartFrame else { return }
        let available = (panel.screen ?? NSScreen.screens.first)?.visibleFrame
        let maxWidth = max(panel.minSize.width, (available?.maxX ?? start.maxX + 1000) - start.minX)
        let maxHeight = max(panel.minSize.height, start.maxY - (available?.minY ?? 0))
        let width = min(maxWidth, max(panel.minSize.width, start.width + translation.width))
        let height = min(maxHeight, max(panel.minSize.height, start.height + translation.height))
        panel.setFrame(NSRect(x: start.minX, y: start.maxY - height, width: width, height: height), display: true)
    }
}

private final class BadgeHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct BadgeDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> BadgeDragRegion {
        let view = BadgeDragRegion()
        view.toolTip = "Drag to move the badge"
        return view
    }
    func updateNSView(_ nsView: BadgeDragRegion, context: Context) {}
}

private final class BadgeDragRegion: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

private struct TaskBadgeView: View {
    @ObservedObject var model: FlowDoModel
    var resize: (CGSize) -> Void
    var endResize: () -> Void
    var body: some View {
        VStack(spacing: 0) {
        BadgeDragHandle()
            .frame(height: 18)
            .overlay(Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 28, height: 3)
                .allowsHitTesting(false))
        ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                OrbView(model: model, animationsEnabled: model.badgeVisible)
                Text(model.currentTask?.title ?? "").font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    Text("\(FlowDoModel.formattedTime(model.sessionTime)) / \(FlowDoModel.formattedTime(model.totalTaskTime))")
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FlowDoModel.formattedTime(model.sessionTime))
                        Text("/ \(FlowDoModel.formattedTime(model.totalTaskTime))")
                    }
                }
                .font(.system(.callout, design: .monospaced)).monospacedDigit()
            }
        }
        .padding(12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.15)))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color(nsColor: .windowBackgroundColor))
                .contentShape(Rectangle())
                .gesture(DragGesture(coordinateSpace: .global)
                    .onChanged { resize($0.translation) }
                    .onEnded { _ in endResize() })
                .help("Drag to resize the badge")
                .accessibilityLabel("Resize task badge")
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
