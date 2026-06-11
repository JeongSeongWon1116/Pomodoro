//
//  PomodoroTests.swift
//  PomodoroTests
//
//  Created by 정성원 on 8/1/25.
//

import Testing
@testable import Pomodoro

@MainActor
struct ObsidianMarkdownTests {

    private let line = "- 🍅 집중 25분 (09:00–09:25)"
    private let heading = ObsidianExporter.sectionHeading

    @Test func 빈_노트에는_헤딩과_함께_추가된다() {
        let result = ObsidianExporter.insert(line: line, into: "")
        #expect(result == "\(heading)\n\(line)\n")
    }

    @Test func 헤딩이_없는_노트에는_맨_아래에_섹션이_생긴다() {
        let result = ObsidianExporter.insert(line: line, into: "# 데일리 노트\n오늘의 메모")
        #expect(result == "# 데일리 노트\n오늘의 메모\n\n\(heading)\n\(line)\n")
    }

    @Test func 기존_섹션의_끝에_줄이_추가된다() {
        let content = "\(heading)\n- ☕️ 짧은 휴식 5분 (08:55–09:00)\n"
        let result = ObsidianExporter.insert(line: line, into: content)
        #expect(result == "\(heading)\n- ☕️ 짧은 휴식 5분 (08:55–09:00)\n\(line)\n")
    }

    @Test func 다음_헤딩_앞에_삽입되어_다른_섹션을_침범하지_않는다() {
        let content = "\(heading)\n- ☕️ 짧은 휴식 5분 (08:55–09:00)\n\n## 할 일\n- 회의 준비\n"
        let result = ObsidianExporter.insert(line: line, into: content)
        #expect(result == "\(heading)\n- ☕️ 짧은 휴식 5분 (08:55–09:00)\n\(line)\n\n## 할 일\n- 회의 준비\n")
    }
}
