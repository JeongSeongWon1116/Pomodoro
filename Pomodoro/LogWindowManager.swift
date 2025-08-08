import SwiftUI
import AppKit
import SwiftData

class LogWindowManager {
    private var logWindow: NSWindow?
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func showLogWindow() {
        if logWindow == nil {
            let logView = LogView()
                .environment(\.modelContext, self.modelContext)

            let hostingController = NSHostingController(rootView: logView)

            let window = NSWindow(
                contentViewController: hostingController
            )
            window.title = "집중 기록"
            window.isReleasedWhenClosed = false
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

            let initialSize = NSSize(width: 800, height: 600)
            window.setContentSize(initialSize)
            window.center()

            self.logWindow = window
        }

        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
