import Foundation
import Testing
@testable import Pomodoro

@MainActor
struct DailyMissionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar
    }
    private let day = Date(timeIntervalSince1970: 1_792_112_400)

    @Test func 하루에는_한_미션만_있고_수정하면_바뀐다() {
        let store = DailyMissionStore(defaults: nil)
        store.setText("초안", for: day, calendar: calendar)
        store.setText("교정\n마무리", for: day, calendar: calendar)
        #expect(store.missions.count == 1)
        #expect(store.mission(for: day, calendar: calendar).text == "교정 마무리")
    }

    @Test func 로컬_자정에_새_칸이_되고_어제_미션은_남는다() throws {
        let midnight = calendar.startOfDay(for: day)
        let before = midnight.addingTimeInterval(-1)
        let store = DailyMissionStore(defaults: nil)
        store.setText("어제의 글", for: before, calendar: calendar)
        #expect(store.mission(for: midnight, calendar: calendar) == DailyMission())
        #expect(store.mission(for: before, calendar: calendar).text == "어제의 글")
        #expect(DailyMissionStore.dayKey(for: midnight, calendar: calendar) != DailyMissionStore.dayKey(for: before, calendar: calendar))
    }

    @Test func 끝냄을_토글하고_끝낸_뒤에도_고친다() {
        let store = DailyMissionStore(defaults: nil)
        store.toggleDone(for: day, calendar: calendar, now: day)
        #expect(!store.mission(for: day, calendar: calendar).done)
        store.setText("초안", for: day, calendar: calendar)
        store.toggleDone(for: day, calendar: calendar, now: day)
        store.setText("초안 교정", for: day, calendar: calendar)
        #expect(store.mission(for: day, calendar: calendar).doneAt == day)
        store.toggleDone(for: day, calendar: calendar, now: day)
        #expect(!store.mission(for: day, calendar: calendar).done)
        #expect(store.mission(for: day, calendar: calendar).doneAt == nil)
        store.toggleDone(for: day, calendar: calendar, now: day)
        store.setText("  ", for: day, calendar: calendar)
        #expect(store.mission(for: day, calendar: calendar) == DailyMission())
    }

    @Test func JSON_저장_왕복() throws {
        let suite = "DailyMissionTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DailyMissionStore(defaults: defaults)
        store.setText("한 문단", for: day, calendar: calendar)
        store.toggleDone(for: day, calendar: calendar, now: day)
        #expect(DailyMissionStore(defaults: defaults).missions == store.missions)
    }

    @Test func 안내_문구() {
        #expect(DailyMissionText.title == "오늘의 메인 미션")
        #expect(DailyMissionText.encouragement == "이것만 끝내면 오늘은 충분해요")
        #expect(DailyMissionText.done == "끝냄")
    }
}
