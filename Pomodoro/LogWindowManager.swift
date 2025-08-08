import SwiftUI
import AppKit
import SwiftData

class LogWindowManager {
    private var logWindow: NSWindow?
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func showLogWindow() {
        if logWindow == nil {
            // DIAGNOSTIC: Use a simple Text view instead of LogView
            let simpleView = Text("Test Window. If you can see this, the windowing logic is working.")

            let hostingController = NSHostingController(rootView: simpleView)

            let window = NSWindow(
                contentViewController: hostingController
            )
            window.title = "Diagnostic Window"
            window.isReleasedWhenClosed = false
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

            let initialSize = NSSize(width: 400, height: 200)
            window.setContentSize(initialSize)
            window.center()

            self.logWindow = window
        }

        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
