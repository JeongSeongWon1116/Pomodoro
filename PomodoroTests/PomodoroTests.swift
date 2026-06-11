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

    private let heading = ObsidianExporter.sectionHeading
    private let stats = ObsidianExporter.statsPrefix

    @Test func 시간_문자열은_초_단위까지_표시한다() {
        #expect(ObsidianExporter.durationText(1500) == "25분")
        #expect(ObsidianExporter.durationText(1453) == "24분 13초")
        #expect(ObsidianExporter.durationText(42) == "42초")
        #expect(ObsidianExporter.durationText(3723) == "1시간 2분 3초")
        #expect(ObsidianExporter.durationText(0) == "0초")
    }

    @Test func 빈_노트에는_헤딩과_통계와_함께_추가된다() {
        let result = ObsidianExporter.insert(line: "- 🍅 집중 25분 (09:00–09:25)", into: "")
        #expect(result == "\(heading)\n\(stats) 🍅 1회 · 총 25분\n- 🍅 집중 25분 (09:00–09:25)\n")
    }

    @Test func 헤딩이_없는_노트에는_맨_아래에_섹션이_생긴다() {
        let result = ObsidianExporter.insert(line: "- 🍅 집중 25분 (09:00–09:25)", into: "# 데일리 노트\n오늘의 메모")
        #expect(result == "# 데일리 노트\n오늘의 메모\n\n\(heading)\n\(stats) 🍅 1회 · 총 25분\n- 🍅 집중 25분 (09:00–09:25)\n")
    }

    @Test func 통계는_누적되지_않고_하나만_갱신된다() {
        let first = ObsidianExporter.insert(line: "- 🍅 집중 25분 (09:00–09:25)", into: "")
        let second = ObsidianExporter.insert(line: "- 🍅 집중 12분 30초 (09:30–09:42)", into: first)
        #expect(second == "\(heading)\n\(stats) 🍅 2회 · 총 37분 30초\n- 🍅 집중 25분 (09:00–09:25)\n- 🍅 집중 12분 30초 (09:30–09:42)\n")
        #expect(second.components(separatedBy: stats).count == 2) // 통계 줄은 정확히 1개
    }

    @Test func 휴식은_하루_통계에_포함되지_않는다() {
        let result = ObsidianExporter.insert(line: "- ☕️ 짧은 휴식 5분 (09:25–09:30)", into: "")
        #expect(result == "\(heading)\n\(stats) 🍅 0회 · 총 0초\n- ☕️ 짧은 휴식 5분 (09:25–09:30)\n")
    }

    @Test func 다음_헤딩_앞에_삽입되어_다른_섹션을_침범하지_않는다() {
        let content = "\(heading)\n\(stats) 🍅 1회 · 총 25분\n- 🍅 집중 25분 (09:00–09:25)\n\n## 할 일\n- 회의 준비\n"
        let result = ObsidianExporter.insert(line: "- ☕️ 짧은 휴식 5분 (09:25–09:30)", into: content)
        #expect(result == "\(heading)\n\(stats) 🍅 1회 · 총 25분\n- 🍅 집중 25분 (09:00–09:25)\n- ☕️ 짧은 휴식 5분 (09:25–09:30)\n\n## 할 일\n- 회의 준비\n")
    }

    @Test func 기록_줄에서_시간을_초로_파싱한다() {
        #expect(ObsidianExporter.parseDurationSeconds(fromLine: "- 🍅 집중 25분 (09:00–09:25)") == 1500)
        #expect(ObsidianExporter.parseDurationSeconds(fromLine: "- 🍅 집중 12분 30초 (09:30–09:42)") == 750)
        #expect(ObsidianExporter.parseDurationSeconds(fromLine: "- 🍅 집중 1시간 2분 3초 (09:00–10:02)") == 3723)
        #expect(ObsidianExporter.parseDurationSeconds(fromLine: "- 🍅 집중 42초 (09:00–09:00)") == 42)
    }
}
