// File: AppDelegate.swift
// Description: 상태 표시줄 아이콘, 팝오버, 알림 등 AppKit 관련 기능을 관리합니다.

import Cocoa
import SwiftUI
import SwiftData
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    // 다른 앱 화면을 클릭했을 때 팝오버를 닫기 위한 전역 마우스 이벤트 모니터.
    // .transient 동작은 우리 앱 안의 클릭만 감지하므로, 로그 창 등 다른 윈도우가
    // 열려 있는 상태에서 외부 앱을 클릭하면 팝오버가 닫히지 않는 문제가 있습니다.
    private var popoverEventMonitor: Any?

    var modelContext: ModelContext?
    private var pomodoroViewModel: PomodoroViewModel!

    // 앱 실행 초기 단계에서 중복 실행 체크
    func applicationWillFinishLaunching(_ notification: Notification) {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if runningApps.count > 1 {
            // 기존 앱 활성화하고 새 인스턴스 즉시 종료
            for app in runningApps where app != NSRunningApplication.current {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            // 즉시 종료 (exit 사용)
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard let modelContext = modelContext else {
            fatalError("AppDelegate에 ModelContext가 제공되지 않았습니다.")
        }

        // ViewModel에 AppDelegate 참조를 전달하여 팝오버를 제어할 수 있도록 합니다.
        self.pomodoroViewModel = PomodoroViewModel(modelContext: modelContext, appDelegate: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            let hostingView = NSHostingView(rootView: StatusBarView().environmentObject(pomodoroViewModel))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor)
            ])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 260, height: 300)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView()
               .environmentObject(pomodoroViewModel)
               .environment(\.modelContext, modelContext)
        )
        
        UNUserNotificationCenter.current().delegate = self
        
        Task {
            await pomodoroViewModel.requestNotificationPermission()
        }
    }

    @objc func togglePopover(_ sender: AnyObject? = nil) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            Task {
                await pomodoroViewModel.checkNotificationSettings()
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            startPopoverEventMonitor()
        }
    }

    // 전역 모니터는 다른 앱에서 발생한 이벤트만 전달받으므로,
    // 외부 앱 클릭 시 팝오버를 닫는 용도로 정확히 들어맞습니다.
    private func startPopoverEventMonitor() {
        guard popoverEventMonitor == nil else { return }
        popoverEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopPopoverEventMonitor() {
        if let monitor = popoverEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverEventMonitor = nil
        }
    }

    // transient 동작 등 어떤 경로로 닫히든 모니터를 함께 해제합니다.
    func popoverDidClose(_ notification: Notification) {
        stopPopoverEventMonitor()
    }
    
    // 토글과 달리 이미 닫혀 있으면 다시 열지 않습니다.
    // performClose()는 다른 윈도우가 키를 가져간 직후에는 무시될 수 있어
    // (예: 이미 열린 로그 창을 다시 앞으로 가져온 경우) close()로 강제로 닫습니다.
    public func closePopover() {
        if popover.isShown {
            popover.close()
        }
        stopPopoverEventMonitor()
    }

    // 세션 종료 시 팝오버를 앞으로 가져오는 public 메서드
    public func bringPopoverToFront() {
        if !popover.isShown {
            togglePopover()
        } else {
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // 앱이 활성화된 상태에서도 알림이 보이도록 설정합니다.
    // .list 제거: 알림 센터에 저장하지 않아 클릭할 수 없게 함
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // 알림 클릭 시 아무 동작도 하지 않음 (새 앱 인스턴스 실행 방지)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 아무것도 하지 않고 완료 처리
        completionHandler()
    }

    // 마지막 윈도우가 닫혀도 앱이 종료되지 않도록 합니다 (메뉴 바 앱)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // 앱 종료 시 알림 취소
    func applicationWillTerminate(_ notification: Notification) {
        pomodoroViewModel?.cancelAllNotifications()
    }
}
