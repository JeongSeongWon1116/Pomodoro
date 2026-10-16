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
        #expect(DailyMissionText(locale: Locale(identifier: "ko")).title == "오늘의 메인 미션")
        #expect(DailyMissionText(locale: Locale(identifier: "ko")).encouragement == "이것만 끝내면 오늘은 충분해요")
        #expect(DailyMissionText(locale: Locale(identifier: "ko")).done == "끝냄")
    }

    @Test func 미션_입력은_편집을_끝낼_때_최종값만_한번_내보낸다() {
        let store = DailyMissionStore(defaults: nil)
        var writes: [DailyMission] = []
        let editor = DailyMissionEditor { mission, _ in writes.append(mission) }
        for text in ["ㅊ", "초", "초아", "초안"] {
            editor.setText(text, in: store, for: day)
        }
        #expect(store.mission(for: day).text == "초안")
        #expect(writes.isEmpty)
        editor.flush() // 제출
        #expect(writes == [DailyMission(text: "초안")])
        editor.flush() // 뒤따르는 포커스 해제와 닫기는 중복 기록하지 않습니다.
        editor.flush()
        #expect(writes.count == 1)
        editor.setText("교정", in: store, for: day)
        editor.flush()
        #expect(writes.map(\.text) == ["초안", "교정"])
    }

    @Test func 같은_미션이나_원래대로_돌린_입력은_내보내지_않는다() {
        let store = DailyMissionStore(defaults: nil)
        var writes: [DailyMission] = []
        let editor = DailyMissionEditor { mission, _ in writes.append(mission) }
        editor.setText(" \t ", in: store, for: day)
        editor.flush()
        store.setText("초안 교정", for: day)
        editor.setText("초안\n교정", in: store, for: day)
        editor.flush()
        editor.setText("다른 글", in: store, for: day)
        editor.setText("초안 교정", in: store, for: day)
        editor.flush()
        #expect(writes.isEmpty)
    }

    @Test func 미션을_지우거나_끝냄을_바꾸면_변경값만_내보낸다() {
        let store = DailyMissionStore(defaults: nil)
        var writes: [DailyMission] = []
        let editor = DailyMissionEditor { mission, _ in writes.append(mission) }
        editor.setText("초안", in: store, for: day)
        editor.toggleDone(in: store, for: day)
        editor.flush()
        #expect(writes.count == 1)
        #expect(writes.first?.text == "초안")
        #expect(writes.first?.done == true)
        editor.setText("", in: store, for: day)
        editor.flush()
        #expect(writes.last == DailyMission())
        editor.toggleDone(in: store, for: day) // 빈 미션의 토글은 값이 바뀌지 않습니다.
        editor.flush()
        #expect(writes.count == 2)
    }

    @Test func 자정을_넘긴_편집도_원래_날짜에_내보낸다() throws {
        let store = DailyMissionStore(defaults: nil)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: day))
        var writes: [String: DailyMission] = [:]
        let editor = DailyMissionEditor { mission, date in
            writes[DailyMissionStore.dayKey(for: date)] = mission
        }
        editor.setText("어제의 글", in: store, for: day)
        editor.setText("오늘의 글", in: store, for: tomorrow)
        editor.flush()
        #expect(writes.count == 2)
        #expect(writes[DailyMissionStore.dayKey(for: day)]?.text == "어제의 글")
        #expect(writes[DailyMissionStore.dayKey(for: tomorrow)]?.text == "오늘의 글")
    }
}
