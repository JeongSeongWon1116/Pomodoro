import SwiftUI
import AppKit

class LogWindowManager {
    private var logWindow: NSWindow?
    private let container = DataController.shared.container

    func showLogWindow() {
        if logWindow == nil {
            let logView = LogView().modelContainer(container)
            let hostingController = NSHostingController(rootView: logView)

            let window = NSWindow(
                contentViewController: hostingController
            )
            window.title = "집중 기록"
            window.isReleasedWhenClosed = false
            window.styleMask.insert(.closable)
            window.styleMask.insert(.resizable)
            window.styleMask.insert(.miniaturizable)
            window.styleMask.insert(.titled)

            let initialSize = NSSize(width: 800, height: 600)
            window.setContentSize(initialSize)

            self.logWindow = window
        }

        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
