// File: UpdateInstallGate.swift
// Description: 받아 둔 업데이트를 언제 설치할지 정합니다.
// 설치하면 앱이 꺼졌다 켜지므로, 타이머가 완전히 쉬고 있고 열린 창이 없는 상태가 한동안 이어졌을 때만 설치합니다.

import Foundation

/// 받아 둔 업데이트의 "지금 설치하고 다시 켜기"를 조용해질 때까지 붙잡아 두는 문지기.
///
/// 조용해진 순간에 곧바로 설치하지 않습니다. 팝오버를 닫고 설정 창을 여는 사이처럼 잠깐 조용해 보이는 틈이
/// 있기 때문에, 조용함이 `settleTime` 동안 이어져야 설치합니다. 설치 동작은 실행한 뒤에도 버리지 않습니다 —
/// 끄는 도중에 사용자가 집중을 시작하면 종료를 취소하고 나중에 다시 실행해야 하기 때문입니다.
@MainActor
final class UpdateInstallGate {
    private enum Phase {
        case empty
        case holding
        case installing(userRequested: Bool, startedAt: Date)
    }

    /// 조용함이 이만큼 이어져야 스스로 설치합니다.
    let settleTime: TimeInterval
    /// 설치를 시작했는데 이만큼 지나도 앱이 꺼지지 않으면 다시 붙잡습니다.
    let installTimeout: TimeInterval

    private let now: () -> Date
    private var install: (() -> Void)?
    private var phase: Phase = .empty
    private var quietSince: Date?

    var hasPendingInstall: Bool { install != nil }

    /// 문지기가 스스로 시작한 설치로 앱이 꺼지는 중인지. (사용자가 "지금 설치"를 누른 경우는 아님)
    var isInstallingOnItsOwn: Bool {
        if case .installing(userRequested: false, _) = phase { return true }
        return false
    }

    init(settleTime: TimeInterval = 60, installTimeout: TimeInterval = 30, now: @escaping () -> Date = Date.init) {
        self.settleTime = settleTime
        self.installTimeout = installTimeout
        self.now = now
    }

    /// 업데이트가 준비됐을 때 설치 동작을 맡깁니다. 여기서는 실행하지 않고, 조용함도 지금부터 다시 셉니다.
    /// 다시 맡기면 나중 것만 남습니다.
    func hold(_ install: @escaping () -> Void) {
        self.install = install
        phase = .holding
        quietSince = nil
    }

    /// 지금 조용한지를 잴 때마다 알려 줍니다. 조용함이 `settleTime` 동안 이어졌으면 설치 동작을 실행합니다.
    func update(quiet: Bool) {
        guard install != nil else { return }
        if case .installing(_, let startedAt) = phase {
            // 이미 설치를 시작했습니다. 앱이 곧 꺼질 것이므로 또 실행하지 않습니다.
            // 한참 지나도 살아 있으면(설치 도우미가 실패한 경우 등) 다시 붙잡고 처음부터 셉니다.
            guard now().timeIntervalSince(startedAt) >= installTimeout else { return }
            phase = .holding
            quietSince = nil
        }
        guard quiet else {
            quietSince = nil
            return
        }
        let since = quietSince ?? now()
        quietSince = since
        guard now().timeIntervalSince(since) >= settleTime else { return }
        run(userRequested: false)
    }

    /// 사용자가 "지금 설치"를 눌렀을 때. 조용한지를 따지지 않습니다.
    func installNow() {
        run(userRequested: true)
    }

    /// 설치하려고 앱을 끄던 중에 종료가 취소됐을 때. 다시 붙잡고, 조용함을 처음부터 셉니다.
    func installWasInterrupted() {
        guard install != nil else { return }
        phase = .holding
        quietSince = nil
    }

    /// 맡긴 설치를 버립니다 (자동 설치를 껐을 때. 앱을 끌 때 설치되는 것은 Sparkle 이 따로 합니다).
    func discard() {
        install = nil
        phase = .empty
        quietSince = nil
    }

    private func run(userRequested: Bool) {
        guard let install else { return }
        // 먼저 상태를 바꿉니다. 설치 동작이 앱을 끝내면서 이 문지기를 다시 부를 수 있습니다.
        phase = .installing(userRequested: userRequested, startedAt: now())
        install()
    }
}

/// 지금 앱을 껐다 켜도 사용자가 잃는 것이 없는 때인지.
enum UpdateQuietness {
    /// 타이머가 완전히 대기이고(세션도, 준비해 둔 다음 세션도 없음) 팝오버와 창이 모두 닫혀 있을 때만 참.
    /// 준비만 해 둔 대기(`currentState`가 대기가 아님)는 긴 휴식까지의 횟수를 들고 있어서 조용한 때로 치지 않습니다.
    static func isQuiet(currentState: PomodoroState, timerState: TimerState, popoverShown: Bool, openWindows: Int) -> Bool {
        currentState == .idle && timerState == .idle && !popoverShown && openWindows == 0
    }

    /// 열려 있는 창의 수. 제목 줄이 있는 창(기록, 설정, 업데이트 안내)만 셉니다 — 메뉴 바 항목과 팝오버도 창이지만
    /// 제목 줄이 없습니다. Dock 에 최소화해 둔 창은 보이지 않아도 열린 창입니다(앱을 다시 켜면 사라집니다).
    static func openWindowCount(_ windows: [(visible: Bool, miniaturized: Bool, titled: Bool)]) -> Int {
        windows.filter { $0.titled && ($0.visible || $0.miniaturized) }.count
    }
}
