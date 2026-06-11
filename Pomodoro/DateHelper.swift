// File: DateHelper.swift
// Description: 일관된 날짜 계산을 제공하는 유틸리티입니다.

import Foundation

struct DateHelper {
    // 사용자의 로컬 시간대 기준 자정을 반환합니다.
    // UTC 기준으로 그룹핑하면 한국(UTC+9)에서는 오전 9시 이전 기록이
    // 전날로 분류되는 등 실제 달력 날짜와 어긋납니다.
    static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
