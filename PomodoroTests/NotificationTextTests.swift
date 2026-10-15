//
//  NotificationTextTests.swift
//  PomodoroTests
//
//  알림 문구(1.3): 다그치지 않고 다음 행동을 묻는 말, 휴식 추천과 다음 시작점 한 줄.
//

import Testing
@testable import Pomodoro

struct NotificationTextTests {

    /// 피하는 말 — 느낌표와 실패 · 부족을 말하는 낱말
    private static let avoided = ["!", "실패", "부족", "미달", "끊김"]

    private func expectGentle(_ text: NotificationText.Content) {
        for word in Self.avoided {
            #expect(!text.title.contains(word), "제목에 '\(word)'")
            #expect(!text.body.contains(word), "본문에 '\(word)'")
        }
    }

    // MARK: - 집중이 끝나 선택을 기다릴 때

    @Test func 집중이_끝나면_계속할지_쉴지_묻는다() {
        let text = NotificationText.focusEnded(reward: "")
        #expect(text.title == "집중이 끝났어요")
        #expect(text.body.contains("\(Int(PomodoroViewModel.focusExtension / 60))분 더 할까요, 쉴까요?"))
        #expect(!text.body.contains("보상"))
        expectGentle(text)
    }

    @Test func 적어_둔_보상이_있으면_먼저_보여_준다() {
        let text = NotificationText.focusEnded(reward: "  커피  ")
        #expect(text.body.hasPrefix("보상: 커피\n"))
        expectGentle(text)
    }

    // MARK: - 세션이 넘어갈 때

    @Test func 넘어가는_알림은_어느_경우에도_다그치지_않는다() {
        let states: [PomodoroState] = [.focus, .shortBreak, .longBreak]
        for ended in states {
            for next in states where next != ended {
                for auto in [true, false] {
                    let text = NotificationText.sessionTransition(
                        ended: ended, next: next, autoStarting: auto,
                        breakSuggestion: "물 한 잔 마시기", resumeHint: "3쪽 둘째 문단")
                    #expect(text.title == "\(ended.description)이 끝났어요")
                    expectGentle(text)
                }
            }
        }
    }

    @Test func 휴식으로_넘어가면_추천을_한_줄_붙인다() {
        let text = NotificationText.sessionTransition(
            ended: .focus, next: .shortBreak, autoStarting: true,
            breakSuggestion: "물 한 잔 마시기", resumeHint: "")
        #expect(text.body.contains("짧은 휴식을 시작합니다"))
        #expect(text.body.contains("\n추천: 물 한 잔 마시기"))
    }

    @Test func 추천이_비어_있으면_추천_줄이_없다() {
        let text = NotificationText.sessionTransition(
            ended: .focus, next: .longBreak, autoStarting: false,
            breakSuggestion: nil, resumeHint: "")
        #expect(!text.body.contains("추천"))
        #expect(text.body.contains("긴 휴식이 준비되었어요"))
    }

    @Test func 집중으로_넘어가면_다음_시작점을_붙인다() {
        let auto = NotificationText.sessionTransition(
            ended: .shortBreak, next: .focus, autoStarting: true,
            breakSuggestion: "스트레칭", resumeHint: " 3쪽 둘째 문단 ")
        #expect(auto.body.contains("집중을 시작합니다"))
        #expect(auto.body.contains("\n이어서: 3쪽 둘째 문단"))
        #expect(!auto.body.contains("추천"), "집중으로 넘어갈 때는 휴식 추천을 붙이지 않는다")

        let manual = NotificationText.sessionTransition(
            ended: .longBreak, next: .focus, autoStarting: false,
            breakSuggestion: nil, resumeHint: "")
        #expect(manual.body.contains("준비되면 메뉴 바에서 집중을 시작하세요"))
        #expect(!manual.body.contains("이어서"))
    }

    @Test func 상태_이름은_모두_받침으로_끝난다_조사_이_을이_맞다() {
        for state in [PomodoroState.focus, .shortBreak, .longBreak] {
            let last = state.description.unicodeScalars.last!.value
            #expect((0xAC00...0xD7A3).contains(last), "\(state.description)은 한글로 끝난다")
            #expect((last - 0xAC00) % 28 != 0, "\(state.description)에 받침이 없으면 이·을을 바꿔야 한다")
        }
    }

    // MARK: - 휴식 추천

    @Test func 휴식_추천은_돌아가며_고르고_한_바퀴_돌면_처음으로() {
        let all = BreakSuggestion.all
        #expect(all.count >= 4)
        #expect(Set(all).count == all.count, "겹치는 추천이 없다")
        #expect(all.allSatisfy { !$0.isEmpty })
        #expect(BreakSuggestion.pick(0) == all[0])
        #expect(BreakSuggestion.pick(1) == all[1])
        #expect(BreakSuggestion.pick(all.count) == all[0])
        #expect(BreakSuggestion.pick(-1) == all[all.count - 1], "음수가 와도 죽지 않는다")
    }
}
