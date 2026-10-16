import Foundation
import Testing
@testable import Morrowisp

@MainActor
struct RewardListTests {
    @Test func 세_크기의_기본_보상() {
        let store = RewardListStore(defaults: nil, locale: Locale(identifier: "ko"))
        #expect(store.items(in: .small).map(\.name) == ["물 한 잔", "음악 한 곡", "짧은 영상 하나"])
        #expect(store.items(in: .medium).map(\.name) == ["산책", "식사", "드라마 한 편"])
        #expect(store.items(in: .large).map(\.name) == ["외식", "취미 시간", "긴 휴식"])
    }

    @Test func 크기별로_더하고_이름을_바꾸고_지운다() throws {
        let store = RewardListStore(defaults: nil, locale: Locale(identifier: "ko"))
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
        let large = RewardItem(name: "외식", size: .large)
        let small = RewardItem(name: "차", size: .small)
        let medium = RewardItem(name: "산책", size: .medium)
        let anotherSmall = RewardItem(name: "음악", size: .small)
        let menu = NoteFieldMenu.make(rewards: [large, small, medium, anotherSmall,
                                                RewardItem(name: "  ", size: .large)],
                                      suggestions: ["책 읽기", "커피"])
        #expect(menu.isVisible)
        #expect(menu.groups.map(\.size) == [.small, .medium, .large])
        #expect(menu.groups.map(\.items) == [[small, anotherSmall], [medium], [large]])
        #expect(menu.suggestions == ["책 읽기", "커피"])
        #expect(menu.showsHistoryDivider)
    }

    @Test func 빈_이름의_보상만_있으면_메뉴를_보이지_않는다() {
        let menu = NoteFieldMenu.make(rewards: [RewardItem(name: "", size: .small),
                                                RewardItem(name: " \t\n ", size: .large)], suggestions: [])
        #expect(!menu.isVisible)
        #expect(menu.groups.isEmpty)
        #expect(!menu.showsHistoryDivider)
    }

    @Test func 빈_보상과_지난_기록만_있으면_앞에_구분선을_넣지_않는다() {
        let menu = NoteFieldMenu.make(rewards: [RewardItem(name: "  ", size: .medium)], suggestions: ["커피"])
        #expect(menu.isVisible)
        #expect(menu.groups.isEmpty)
        #expect(menu.suggestions == ["커피"])
        #expect(!menu.showsHistoryDivider)
    }

    @Test func 유효한_보상만_크기별로_남기고_빈_그룹은_빼낸다() {
        let reward = RewardItem(name: "산책", size: .medium)
        let menu = NoteFieldMenu.make(rewards: [RewardItem(name: "  ", size: .small), reward,
                                                RewardItem(name: "", size: .medium)], suggestions: [])
        #expect(menu.isVisible)
        #expect(menu.groups.map(\.size) == [.medium])
        #expect(menu.groups.map(\.items) == [[reward]])
        #expect(!menu.showsHistoryDivider)
    }
}
