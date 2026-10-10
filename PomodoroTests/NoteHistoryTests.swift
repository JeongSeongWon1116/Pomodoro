//
//  NoteHistoryTests.swift
//  PomodoroTests
//
//  적어 둔 할 일·보상을 다시 보고(기록 창) 다시 고르는(팝오버) 기능을 검증합니다.
//  (사용자의 설정·기록·보관함을 건드리지 않습니다.)
//

import Foundation
import SwiftData
import Testing
@testable import Pomodoro

struct NoteSuggestionsTests {
    @Test func 최근_것부터_겹치지_않게_고른다() {
        let picked = NoteSuggestions.recent(["논문 3장", "메일 답장", "논문 3장", "코드 리뷰"])
        #expect(picked == ["논문 3장", "메일 답장", "코드 리뷰"])
    }

    @Test func 앞뒤_공백과_대소문자만_다른_글은_같은_글로_본다() {
        let picked = NoteSuggestions.recent(["Coffee", " coffee ", "COFFEE", "산책"])
        #expect(picked == ["Coffee", "산책"])
    }

    @Test func 빈_글과_지금_적혀_있는_글은_뺀다() {
        let picked = NoteSuggestions.recent(["", "   ", "산책", "커피"], excluding: " 산책 ")
        #expect(picked == ["커피"])
    }

    @Test func 정한_개수까지만_고른다() {
        let picked = NoteSuggestions.recent((1...9).map { "할 일 \($0)" }, limit: 5)
        #expect(picked == ["할 일 1", "할 일 2", "할 일 3", "할 일 4", "할 일 5"])
    }

    @Test func 고른_글은_앞뒤_공백을_뗀_모습이다() {
        #expect(NoteSuggestions.recent(["  커피 한 잔\n"]) == ["커피 한 잔"])
    }
}

struct NoteFieldMenuTitleTests {
    @Test func 짧은_글은_그대로_보여_준다() {
        #expect(NoteField.menuTitle("커피 한 잔") == "커피 한 잔")
    }

    @Test func 긴_글은_줄여서_한_줄로_보여_준다() {
        let long = "실험 결과 표 정리하고 그림 3의 캡션과 단위를 다시 확인한 다음 본문 숫자와 맞추기"
        let title = NoteField.menuTitle(long, limit: 10)
        #expect(title == "실험 결과 표 정리…") // 앞 열 글자 + 줄임표
        #expect(NoteField.menuTitle("첫 줄\n둘째 줄") == "첫 줄 둘째 줄")
    }
}

struct TransitionDetailsLinesTests {
    @Test func 적은_것만_이름표와_함께_차례로_낸다() {
        let details = TransitionDetails(task: "논문 3장", reward: "", nextStartingPoint: " 3.2절부터 ", extensionCount: 0)
        #expect(details.labeledLines.map(\.label) == ["할 일", "다음 시작점"])
        #expect(details.labeledLines.map(\.text) == ["논문 3장", "3.2절부터"])
    }

    @Test func 연장한_횟수도_한_줄로_낸다() {
        let details = TransitionDetails(task: "", reward: "커피", nextStartingPoint: "", extensionCount: 2)
        #expect(details.labeledLines.map(\.label) == ["보상", "연장"])
        #expect(details.labeledLines.last?.text == "2회")
    }

    @Test func 적은_것이_없으면_줄이_없다() {
        #expect(TransitionDetails().labeledLines.isEmpty)
    }
}

@MainActor
struct NoteHistoryTests {
    private let clock = TestClock()
    private let settings: AppSettings
    private let container: ModelContainer
    private let notesContainer: ModelContainer
    private let appDelegate = AppDelegate()
    private let viewModel: PomodoroViewModel

    init() throws {
        let settings = AppSettings(defaults: nil)
        settings.notificationSoundName = AppSettings.soundOff
        self.settings = settings
        container = try ModelContainer(for: FocusLogEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        notesContainer = try ModelContainer(for: TransitionNote.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = self.clock
        viewModel = PomodoroViewModel(
            modelContext: container.mainContext, appDelegate: appDelegate, settings: settings,
            notesContext: notesContainer.mainContext, now: { clock.date }
        )
    }

    /// 할 일과 보상을 적고 집중 하나를 끝까지 마친 뒤 휴식을 고릅니다.
    private func finishFocus(task: String, reward: String) {
        viewModel.resetToIdle()
        viewModel.focusTask = task
        viewModel.focusReward = reward
        viewModel.startFocusSession()
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
        viewModel.startBreakAfterFocus()
        clock.advance(60)
    }

    @Test func 처음에는_고를_것이_없다() {
        #expect(viewModel.taskSuggestions.isEmpty)
        #expect(viewModel.rewardSuggestions.isEmpty)
    }

    @Test func 마친_집중의_할_일과_보상이_최근_것부터_고를_것으로_나온다() {
        finishFocus(task: "논문 3장", reward: "커피")
        finishFocus(task: "메일 답장", reward: "산책")
        viewModel.resetToIdle()
        viewModel.focusTask = ""
        viewModel.focusReward = ""

        #expect(viewModel.taskSuggestions == ["메일 답장", "논문 3장"])
        #expect(viewModel.rewardSuggestions == ["산책", "커피"])
    }

    @Test func 지금_적혀_있는_글은_고를_것에서_빠진다() {
        finishFocus(task: "논문 3장", reward: "커피")
        finishFocus(task: "메일 답장", reward: "커피")
        viewModel.resetToIdle()
        viewModel.focusTask = "메일 답장"
        viewModel.focusReward = "커피"

        #expect(viewModel.taskSuggestions == ["논문 3장"])
        #expect(viewModel.rewardSuggestions.isEmpty)
    }

    @Test func 기록을_모두_지운_뒤_다시_읽으면_고를_것이_없다() {
        finishFocus(task: "논문 3장", reward: "커피")
        viewModel.resetToIdle()
        viewModel.focusTask = ""
        #expect(viewModel.taskSuggestions == ["논문 3장"])

        TransitionNote.delete(forSessions: nil, in: notesContainer.mainContext)
        viewModel.refreshNoteSuggestions()
        #expect(viewModel.taskSuggestions.isEmpty)
    }

    @Test func 메모_저장소가_없으면_고를_것이_없고_죽지_않는다() throws {
        let clock = TestClock()
        let bare = PomodoroViewModel(
            modelContext: container.mainContext, appDelegate: appDelegate, settings: settings,
            notesContext: nil, now: { clock.date }
        )
        bare.refreshNoteSuggestions()
        #expect(bare.taskSuggestions.isEmpty)
        #expect(bare.rewardSuggestions.isEmpty)
    }

    @Test func 앱을_다시_켜도_지난_기록에서_고를_수_있다() {
        finishFocus(task: "논문 3장", reward: "커피")
        let clock = TestClock()
        let reopened = PomodoroViewModel(
            modelContext: container.mainContext, appDelegate: appDelegate, settings: AppSettings(defaults: nil),
            notesContext: notesContainer.mainContext, now: { clock.date }
        )
        #expect(reopened.taskSuggestions == ["논문 3장"])
        #expect(reopened.rewardSuggestions == ["커피"])
    }

    @Test func 기록_창은_세션마다_적은_글을_찾아_온다() throws {
        finishFocus(task: "논문 3장", reward: "커피")
        finishFocus(task: "메일 답장", reward: "")
        let logs = try container.mainContext.fetch(FetchDescriptor<FocusLogEntry>(sortBy: [SortDescriptor(\.startTime)]))
        let focusIDs = logs.filter { $0.sessionType == .focus }.map(\.id)
        #expect(focusIDs.count == 2)

        let found = TransitionNote.details(forSessions: logs.map(\.id), in: notesContainer.mainContext)
        #expect(found.count == 2) // 휴식에는 적은 글이 없습니다
        #expect(found[focusIDs[0]]?.task == "논문 3장")
        #expect(found[focusIDs[0]]?.reward == "커피")
        #expect(found[focusIDs[1]]?.task == "메일 답장")

        // 묻지 않은 세션의 글은 오지 않습니다.
        #expect(TransitionNote.details(forSessions: [focusIDs[1]], in: notesContainer.mainContext).keys.map { $0 } == [focusIDs[1]])
        #expect(TransitionNote.details(forSessions: [], in: notesContainer.mainContext).isEmpty)
        #expect(TransitionNote.details(forSessions: focusIDs, in: nil).isEmpty)
    }
}
