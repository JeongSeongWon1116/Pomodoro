import Foundation
import Testing
@testable import Pomodoro

struct LocalizationTests {
    private let english = Locale(identifier: "en")

    @Test func englishFocusNotificationIncludesRewardAndChoice() {
        let text = NotificationText.focusEnded(reward: "  Tea  ", locale: english)
        #expect(text.title == "Focus has ended")
        #expect(text.body == "Reward: Tea\nAnother 10 minutes, or a break? Choose in the menu bar.")
    }

    @Test func englishTransitionsIncludeTheRelevantNextStep() {
        let rest = NotificationText.sessionTransition(
            ended: .focus, next: .shortBreak, autoStarting: true,
            breakSuggestion: BreakSuggestion.pick(0, locale: english), resumeHint: "", locale: english)
        #expect(rest.title == "Focus has ended")
        #expect(rest.body == "Short break is starting.\nSuggestion: Drink a glass of water")

        let focus = NotificationText.sessionTransition(
            ended: .longBreak, next: .focus, autoStarting: false,
            breakSuggestion: nil, resumeHint: "  Page 3  ", locale: english)
        #expect(focus.title == "Long break has ended")
        #expect(focus.body == "When you are ready, start focusing from the menu bar.\nPick up from: Page 3")
    }

    @Test func englishNotificationsStayGentle() {
        for ended in [PomodoroState.focus, .shortBreak, .longBreak] {
            for next in [PomodoroState.focus, .shortBreak, .longBreak] where ended != next {
                for autoStarting in [false, true] {
                    let text = NotificationText.sessionTransition(
                        ended: ended, next: next, autoStarting: autoStarting,
                        breakSuggestion: nil, resumeHint: "", locale: english)
                    for word in ["!", "score", "fail"] {
                        #expect(!text.title.lowercased().contains(word))
                        #expect(!text.body.lowercased().contains(word))
                    }
                }
            }
        }
    }

    @Test func englishBreakSuggestionsWrapInBothDirections() {
        let suggestions = BreakSuggestion.suggestions(locale: english)
        #expect(suggestions == [
            "Drink a glass of water", "Stand up and stretch", "Look out the window",
            "Take a bathroom break", "Have a light snack", "Take a short walk"
        ])
        #expect(BreakSuggestion.pick(suggestions.count, locale: english) == suggestions[0])
        #expect(BreakSuggestion.pick(-1, locale: english) == suggestions.last)
    }

    @Test func englishDailySummaryIncludesCountsAndTask() {
        let summary = DaySummary(focusCount: 2, focusMinutes: 80, extensionCount: 3,
                                 mainTask: "Draft", hasFocus: true)
        #expect(DaySummaryText.line(summary, locale: english)
                == "Focus sessions today: 2 · 80 min · Extensions: 3 · Mostly: Draft")
    }

    @Test func englishEmptyDayInvitesAFirstSession() {
        let summary = DaySummary(focusCount: 0, focusMinutes: 0, extensionCount: 0,
                                 mainTask: nil, hasFocus: false)
        #expect(DaySummaryText.line(summary, locale: english) == "Ready for your first focus session today?")
    }

    @Test func explicitLocalesDoNotDependOnTheHostLanguage() {
        let korean = NotificationText.focusEnded(reward: "", locale: Locale(identifier: "ko"))
        let englishText = NotificationText.focusEnded(reward: "", locale: english)
        #expect(korean.title == "집중이 끝났어요")
        #expect(englishText.title == "Focus has ended")
        #expect(NotificationText.focusEnded(reward: "", locale: Locale(identifier: "fr")).title
                == englishText.title)
    }

    @Test func summaryNumbersFollowTheRequestedLocale() {
        let summary = DaySummary(focusCount: 1, focusMinutes: 1234, extensionCount: 0,
                                 mainTask: nil, hasFocus: true)
        let locale = Locale(identifier: "en_US")
        #expect(DaySummaryText.line(summary, locale: locale).contains("1,234 min"))
    }

    @MainActor
    @Test func englishRewardExamplesLeaveSavedRewardsUntouched() throws {
        let suite = "LocalizationTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RewardListStore(defaults: defaults, locale: english)
        #expect(store.items(in: .small).map(\.name) == ["A glass of water", "A song", "A short video"])
        let reward = try #require(store.items.first)
        store.rename(reward.id, to: "내가 적은 보상")
        let reopened = RewardListStore(defaults: defaults, locale: Locale(identifier: "ko"))
        #expect(reopened.items == store.items)
    }

    @Test func everyCatalogKeyHasAKoreanTranslation() throws {
        // Read the source catalog, not generated .strings files, to catch missing translations.
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Pomodoro/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
        #expect(catalog.sourceLanguage == "en")
        #expect(!catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            let unit = try #require(entry.localizations["ko"]?.stringUnit, "Missing Korean: \(key)")
            #expect(unit.state == "translated", "Untranslated Korean: \(key)")
            #expect(!unit.value.isEmpty, "Empty Korean: \(key)")
        }
    }

    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]

        struct Entry: Decodable {
            let localizations: [String: Translation]
        }
        struct Translation: Decodable {
            let stringUnit: Unit?
        }
        struct Unit: Decodable {
            let state: String
            let value: String
        }
    }
}
