// File: UpdateInstallGate.swift
// Description: 받아 둔 업데이트를 언제 설치할지 정합니다.
// 설치하면 앱이 꺼졌다 켜지므로, 타이머가 완전히 쉬고 있고 열린 창이 없을 때만 설치합니다.

import Foundation

/// 받아 둔 업데이트의 "지금 설치하고 다시 켜기"를 조용해질 때까지 붙잡아 두는 문지기.
@MainActor
final class UpdateInstallGate {
    private var pendingInstall: (() -> Void)?
    private var quiet: Bool

    var hasPendingInstall: Bool { pendingInstall != nil }

    init(quiet: Bool = false) {
        self.quiet = quiet
    }

    /// 업데이트가 준비됐을 때 설치 동작을 맡깁니다. 조용하면 곧바로, 아니면 조용해질 때 한 번 실행합니다.
    /// 다시 맡기면 나중 것만 남습니다.
    func hold(_ install: @escaping () -> Void) {
        pendingInstall = install
        installIfQuiet()
    }

    /// 조용한지가 바뀌었을 때(또는 다시 쟀을 때) 알려 줍니다.
    func update(quiet: Bool) {
        self.quiet = quiet
        installIfQuiet()
    }

    /// 맡긴 설치를 버립니다 (업데이트가 취소됐거나 다른 길로 설치됨).
    func discard() {
        pendingInstall = nil
    }

    private func installIfQuiet() {
        guard quiet, let install = pendingInstall else { return }
        // 먼저 비웁니다. 설치 동작이 앱을 끝내면서 이 문지기를 다시 부를 수 있습니다.
        pendingInstall = nil
        install()
    }
}

/// 지금 앱을 껐다 켜도 사용자가 잃는 것이 없는 때인지.
enum UpdateQuietness {
    /// 타이머가 완전히 대기이고(세션도, 준비해 둔 다음 세션도 없음) 팝오버와 창이 모두 닫혀 있을 때만 참.
    /// 준비만 해 둔 대기(`currentState`가 대기가 아님)는 긴 휴식까지의 횟수를 들고 있어서 조용한 때로 치지 않습니다.
    static func isQuiet(currentState: PomodoroState, timerState: TimerState, popoverShown: Bool, visibleWindows: Int) -> Bool {
        currentState == .idle && timerState == .idle && !popoverShown && visibleWindows == 0
    }
}
