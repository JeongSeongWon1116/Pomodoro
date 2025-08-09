import SwiftUI
import AppKit
import SwiftData

class LogWindowController: NSWindowController {
    convenience init(container: ModelContainer) {
        let logView = LogView().modelContainer(container)
        let hostingController = NSHostingController(rootView: logView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "집중 기록"
        window.isReleasedWhenClosed = false
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        let initialSize = NSSize(width: 800, height: 600)
        window.setContentSize(initialSize)
        window.center()

        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
