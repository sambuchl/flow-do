import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = StatusItemController(model: FlowDoModel())
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = controller?.model else { return .terminateNow }
        Task { @MainActor in
            // Let an in-flight atomic task write finish before flushing totals/logs.
            while model.busy { try? await Task.sleep(nanoseconds: 20_000_000) }
            model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func willSleep() { controller?.model.suspend(reason: "sleep") }
    @objc private func didWake() { controller?.model.resume(reason: "sleep") }
    @objc private func sessionResigned() { controller?.model.suspend(reason: "session_inactive") }
    @objc private func sessionActivated() { controller?.model.resume(reason: "session_inactive") }
}
