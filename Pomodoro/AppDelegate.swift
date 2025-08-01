import Cocoa
import SwiftUI

// 섹션 2.2.1의 계획에 따라 NSApplicationDelegate를 준수하는 AppDelegate 클래스를 생성합니다.[1]
class AppDelegate: NSObject, NSApplicationDelegate {

    // 메뉴 막대 아이템과 팝오버는 앱의 생명주기 동안 유지되어야 하므로 프로퍼티로 선언합니다.
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // PomodoroApp에서 주입받을 ViewModel에 대한 참조입니다.
    // 이 참조를 통해 AppKit 객체들이 앱의 중앙 상태에 접근할 수 있습니다.
    var pomodoroViewModel: PomodoroViewModel!

    // applicationDidFinishLaunching는 앱이 실행 준비를 마쳤을 때 호출되는 메서드입니다.
    // 이곳에서 SwiftUI 생명주기 외부에서 관리되어야 하는 모든 AppKit 객체를 설정합니다.[1]
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        // --- 1. NSStatusItem 설정 (계획서 섹션 2.2.1) ---
        // 시스템 상태 표시줄에 가변 길이의 아이템을 생성합니다.
        //.variableLength는 내용물의 크기에 따라 너비가 동적으로 조절되도록 합니다.[1]
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else {
            print("Status bar item's button could not be created.")
            return
        }
        
        // 버튼 클릭 시 togglePopover 메서드가 호출되도록 액션을 설정합니다.
        button.action = #selector(togglePopover(_:))

        // --- 2. SwiftUI 뷰를 AppKit에 호스팅 (계획서 섹션 2.1.3) ---
        // StatusBarView를 생성하고, PomodoroApp에서 전달받은 viewModel을 환경 객체로 주입합니다.
        // 이것이 AppKit에 호스팅된 뷰가 SwiftUI의 상태를 구독하는 핵심 연결 고리입니다.
        let statusBarView = StatusBarView().environmentObject(pomodoroViewModel)
        
        // NSHostingView는 SwiftUI 뷰를 감싸서 AppKit 뷰 계층에 추가할 수 있는 NSView 하위 클래스입니다.[1]
        let hostingView = NSHostingView(rootView: statusBarView)
        
        // 상태 표시줄의 표준 높이에 맞춰 프레임을 명시적으로 설정합니다.
        // 너비는 내용물(시간, 진행률)에 맞게 적절히 조절합니다.
        hostingView.frame = NSRect(x: 0, y: 0, width: 75, height: 22)
        
        // 호스팅 뷰를 상태 표시줄 버튼의 하위 뷰로 추가하여 화면에 표시합니다.
        button.addSubview(hostingView)


        // --- 3. NSPopover 설정 (계획서 섹션 3.1.1) ---
        let settingsView = SettingsView().environmentObject(pomodoroViewModel)
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 320)
        //.transient 동작은 팝오버 외부를 클릭하면 자동으로 닫히게 하여
        // 일반적인 메뉴 막대 앱의 사용자 경험을 제공합니다.[1]
        popover.behavior = .transient
        // 팝오버의 콘텐츠로 SwiftUI 뷰를 호스팅하는 NSHostingController를 사용합니다.
        popover.contentViewController = NSHostingController(rootView: settingsView)
    }

    // 상태 표시줄 아이콘을 클릭했을 때 호출되는 @objc 메서드입니다.
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            // 팝오버가 이미 표시되어 있다면 닫습니다.
            popover.performClose(sender)
        } else {
            // 팝오버를 표시합니다. relativeTo와 preferredEdge를 사용하여
            // 상태 표시줄 아이콘 바로 아래에 나타나도록 위치를 지정합니다.[1]
            popover.show(relativeTo: button.bounds, of: button, preferredEdge:.minY)
            // 팝오버가 키 윈도우가 되도록 하여 즉시 사용자 입력을 받을 수 있게 합니다.
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}
