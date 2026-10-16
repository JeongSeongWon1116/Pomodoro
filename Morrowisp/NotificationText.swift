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
    nonisolated static func focusEnded(reward: String, locale: Locale = .current) -> Content {
        let reward = reward.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int(PomodoroViewModel.focusExtension / 60)
        let prompt = String(localized: "Another \(minutes.formatted(.number.locale(locale))) minutes, or a break? Choose in the menu bar.", bundle: AppLocalization.bundle(for: locale), locale: locale)
        return Content(
            title: String(localized: "\(PomodoroState.focus.localizedDescription(locale: locale)) has ended", bundle: AppLocalization.bundle(for: locale), locale: locale),
            body: reward.isEmpty ? prompt : String(localized: "Reward: \(reward)\n\(prompt)", bundle: AppLocalization.bundle(for: locale), locale: locale)
        )
    }

    /// 한 세션이 끝나고 다음으로 넘어갈 때.
    /// 휴식으로 넘어가면 breakSuggestion 을, 집중으로 넘어가면 resumeHint(다음 시작점)를 한 줄 붙입니다.
    nonisolated static func sessionTransition(
        ended: PomodoroState,
        next: PomodoroState,
        autoStarting: Bool,
        breakSuggestion: String?,
        resumeHint: String,
        locale: Locale = .current
    ) -> Content {
        // 상태 이름(집중 · 짧은 휴식 · 긴 휴식)은 모두 받침으로 끝나 "이 · 을"을 씁니다.
        var body: String
        if next == .focus {
            body = autoStarting ? String(localized: "Starting focus.", bundle: AppLocalization.bundle(for: locale), locale: locale) : String(localized: "When you are ready, start focusing from the menu bar.", bundle: AppLocalization.bundle(for: locale), locale: locale)
            let hint = resumeHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hint.isEmpty { body += String(localized: "\nPick up from: \(hint)", bundle: AppLocalization.bundle(for: locale), locale: locale) }
        } else {
            body = autoStarting
                ? String(localized: "\(next.localizedDescription(locale: locale)) is starting.", bundle: AppLocalization.bundle(for: locale), locale: locale)
                : String(localized: "\(next.localizedDescription(locale: locale)) is ready. Start from the menu bar.", bundle: AppLocalization.bundle(for: locale), locale: locale)
            if let suggestion = breakSuggestion, !suggestion.isEmpty { body += String(localized: "\nSuggestion: \(suggestion)", bundle: AppLocalization.bundle(for: locale), locale: locale) }
        }
        return Content(title: String(localized: "\(ended.localizedDescription(locale: locale)) has ended", bundle: AppLocalization.bundle(for: locale), locale: locale), body: body)
    }
}

/// 짧고 끝이 있는 휴식 거리. 강한 자극으로 흐르지 않게 몸을 움직이는 것 위주입니다.
enum BreakSuggestion {
    nonisolated static var all: [String] { suggestions() }

    nonisolated static func suggestions(locale: Locale = .current) -> [String] {
        [
            String(localized: "Drink a glass of water", bundle: AppLocalization.bundle(for: locale), locale: locale),
            String(localized: "Stand up and stretch", bundle: AppLocalization.bundle(for: locale), locale: locale),
            String(localized: "Look out the window", bundle: AppLocalization.bundle(for: locale), locale: locale),
            String(localized: "Take a bathroom break", bundle: AppLocalization.bundle(for: locale), locale: locale),
            String(localized: "Have a light snack", bundle: AppLocalization.bundle(for: locale), locale: locale),
            String(localized: "Take a short walk", bundle: AppLocalization.bundle(for: locale), locale: locale),
        ]
    }

    /// index 번째 추천 (한 바퀴 돌면 처음으로). 마친 집중 수를 넣으면 휴식마다 바뀝니다.
    nonisolated static func pick(_ index: Int, locale: Locale = .current) -> String {
        let all = suggestions(locale: locale)
        let n = all.count
        return all[((index % n) + n) % n]
    }
}
