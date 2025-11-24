// File: AppDelegate.swift
// Description: 상태 표시줄 아이콘, 팝오버, 알림 등 AppKit 관련 기능을 관리합니다.

import Cocoa
import SwiftUI
import SwiftData
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    
    var modelContext: ModelContext?
    private var pomodoroViewModel: PomodoroViewModel!
    
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
        popover.contentSize = NSSize(width: 260, height: 380)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: SettingsView()
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
        }
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
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    // 알림 클릭 시 기존 앱을 활성화 (새 인스턴스 방지)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 앱을 활성화하고 팝오버 표시
        NSApp.activate(ignoringOtherApps: true)
        togglePopover()
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
