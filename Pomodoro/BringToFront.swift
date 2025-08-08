import SwiftUI

struct BringToFront: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // A new window opened via SwiftUI will be the key window at this point.
            if let window = NSApp.keyWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
