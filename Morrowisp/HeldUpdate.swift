// File: HeldUpdate.swift
// Description: 받아 둔 업데이트의 "설치하고 다시 켜기"를 사용자가 누를 때까지 들고 있습니다.

import Foundation

/// 받아 둔 업데이트의 설치 동작을 들고 있는 것.
///
/// 스스로는 실행하지 않습니다 — 사용자가 "업데이트"를 누를 때만 실행합니다. (누르지 않은 채 앱을 끄면 Sparkle 이 그때 설치합니다.)
/// 설치 동작은 실행한 뒤에도 버리지 않습니다. 실행했는데 앱이 꺼지지 않으면(설치 도우미가 실패한 경우 등)
/// `installTimeout` 뒤에 다시 누를 수 있어야 하기 때문입니다.
@MainActor
final class HeldUpdate {
    /// 설치를 시작했는데 이만큼(초) 지나도 앱이 꺼지지 않으면 다시 누를 수 있게 합니다.
    let installTimeout: TimeInterval

    // 깨어 있는 동안만 가는 시계(초)
    private let now: () -> TimeInterval
    private var install: (() -> Void)?
    private var installStartedAt: TimeInterval?

    /// 설치 동작을 들고 있는지.
    var isHolding: Bool { install != nil }

    /// 설치 동작을 실행했고 앱이 꺼지기를 기다리는 중인지. 한참 지나도 앱이 살아 있으면 거짓으로 돌아옵니다.
    var isInstalling: Bool {
        guard install != nil, let installStartedAt else { return false }
        return now() - installStartedAt < installTimeout
    }

    init(
        installTimeout: TimeInterval = 30,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.installTimeout = installTimeout
        self.now = now
    }

    /// 업데이트가 준비됐을 때 설치 동작을 맡깁니다. 여기서는 실행하지 않습니다. 다시 맡기면 나중 것만 남습니다.
    func hold(_ install: @escaping () -> Void) {
        self.install = install
        installStartedAt = nil
    }

    /// 사용자가 "업데이트"를 눌렀을 때 설치 동작을 실행합니다. 실행했으면 참.
    /// 맡긴 것이 없거나 방금 시작한 설치가 아직 진행 중이면 아무것도 하지 않습니다.
    @discardableResult
    func installNow() -> Bool {
        guard let install, !isInstalling else { return false }
        // 먼저 상태를 바꿉니다. 설치 동작이 앱을 끝내면서 이쪽을 다시 부를 수 있습니다.
        installStartedAt = now()
        install()
        return true
    }

    /// 맡긴 설치를 버립니다 (Sparkle 의 업데이트 주기가 끝나 그 설치 동작을 더 쓸 수 없을 때).
    func discard() {
        install = nil
        installStartedAt = nil
    }
}
