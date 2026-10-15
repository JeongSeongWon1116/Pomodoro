// File: NotificationText.swift
// Description: 세션 알림의 제목과 본문, 휴식 추천을 만듭니다 (1.3).
// 다그치지 않고 다음 행동을 묻습니다 — 느낌표, "실패 · 부족" 같은 말을 쓰지 않습니다.

import Foundation

enum NotificationText {
    struct Content: Equatable {
        let title: String
        let body: String
    }

    /// 집중 시간이 다 되어 선택(휴식 / 연장)을 기다릴 때
    nonisolated static func focusEnded(reward: String) -> Content {
        let reward = reward.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int(PomodoroViewModel.focusExtension / 60)
        let prompt = "\(minutes)분 더 할까요, 쉴까요? 메뉴 바에서 고르세요."
        return Content(
            title: "\(PomodoroState.focus.description)이 끝났어요",
            body: reward.isEmpty ? prompt : "보상: \(reward)\n\(prompt)"
        )
    }

    /// 한 세션이 끝나고 다음으로 넘어갈 때.
    /// 휴식으로 넘어가면 breakSuggestion 을, 집중으로 넘어가면 resumeHint(다음 시작점)를 한 줄 붙입니다.
    nonisolated static func sessionTransition(
        ended: PomodoroState,
        next: PomodoroState,
        autoStarting: Bool,
        breakSuggestion: String?,
        resumeHint: String
    ) -> Content {
        // 상태 이름(집중 · 짧은 휴식 · 긴 휴식)은 모두 받침으로 끝나 "이 · 을"을 씁니다.
        var body: String
        if next == .focus {
            body = autoStarting ? "집중을 시작합니다." : "준비되면 메뉴 바에서 집중을 시작하세요."
            let hint = resumeHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hint.isEmpty { body += "\n이어서: \(hint)" }
        } else {
            body = autoStarting
                ? "\(next.description)을 시작합니다."
                : "\(next.description)이 준비되었어요. 메뉴 바에서 시작하세요."
            if let suggestion = breakSuggestion, !suggestion.isEmpty { body += "\n추천: \(suggestion)" }
        }
        return Content(title: "\(ended.description)이 끝났어요", body: body)
    }
}

/// 짧고 끝이 있는 휴식 거리. 강한 자극으로 흐르지 않게 몸을 움직이는 것 위주입니다.
enum BreakSuggestion {
    nonisolated static let all = [
        "물 한 잔 마시기",
        "자리에서 일어나 스트레칭",
        "창밖 보기",
        "화장실 다녀오기",
        "가벼운 간식",
        "짧은 산책",
    ]

    /// index 번째 추천 (한 바퀴 돌면 처음으로). 마친 집중 수를 넣으면 휴식마다 바뀝니다.
    nonisolated static func pick(_ index: Int) -> String {
        let n = all.count
        return all[((index % n) + n) % n]
    }
}
