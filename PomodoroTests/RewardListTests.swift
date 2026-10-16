import Foundation
import Testing
@testable import Pomodoro

@MainActor
struct RewardListTests {
    @Test func 세_크기의_기본_보상() {
        let store = RewardListStore(defaults: nil)
        #expect(store.items(in: .small).map(\.name) == ["물 한 잔", "음악 한 곡", "짧은 영상 하나"])
        #expect(store.items(in: .medium).map(\.name) == ["산책", "식사", "드라마 한 편"])
        #expect(store.items(in: .large).map(\.name) == ["외식", "취미 시간", "긴 휴식"])
    }

    @Test func 크기별로_더하고_이름을_바꾸고_지운다() throws {
        let store = RewardListStore(defaults: nil)
        store.add(" 커피 ", size: .small)
        let item = try #require(store.items(in: .small).last)
        #expect(item.name == "커피")
        #expect(store.items(in: .medium).count == 3)
        store.rename(item.id, to: "차 한 잔")
        #expect(store.items(in: .small).last?.name == "차 한 잔")
        store.remove(item.id)
        #expect(store.items(in: .small).count == 3)
        store.add(" \n ", size: .large)
        #expect(store.items(in: .large).count == 3)
    }

    @Test func 모두_지운_뒤_다시_열어도_예시가_생기지_않는다() throws {
        let suite = "RewardListTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RewardListStore(defaults: defaults)
        for item in store.items { store.remove(item.id) }
        #expect(RewardListStore(defaults: defaults).items.isEmpty)
        store.add("책 읽기", size: .large)
        #expect(RewardListStore(defaults: defaults).items == store.items)
    }

    @Test func 보상_메뉴는_크기_순서와_지난_기록을_구분한다() {
        #expect(RewardSize.allCases.map(\.title) == ["작은", "중간", "큰"])
        #expect(RewardListText.history == "지난 보상")
    }
}
