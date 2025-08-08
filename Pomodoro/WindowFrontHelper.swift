import SwiftUI

struct WindowFrontHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Use a dispatch queue to allow the view and window to be set up first.
        DispatchQueue.main.async {
            if let window = view.window {
                // Deactivating and then reactivating is a more forceful way to
                // ensure the application and its window come to the front.
                NSApp.deactivate()
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
