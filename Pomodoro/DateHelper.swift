// File: DateHelper.swift
// Description: 시간대와 무관하게 일관된 날짜 계산을 제공하는 유틸리티입니다.

import Foundation

struct DateHelper {
    // 항상 UTC 시간대를 사용하는 캘린더
    static var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        guard let utcTimeZone = TimeZone(secondsFromGMT: 0) else {
            fatalError("UTC 시간대를 생성할 수 없습니다.")
        }
        calendar.timeZone = utcTimeZone
        return calendar
    }()

    // 주어진 날짜의 UTC 기준 시작 시각(자정)을 반환합니다.
    static func startOfDayUTC(for date: Date) -> Date {
        return utcCalendar.startOfDay(for: date)
    }
}
