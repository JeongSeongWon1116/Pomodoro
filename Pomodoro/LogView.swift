import SwiftUI
import SwiftData
import Charts

// 차트에 사용하기 위한 집계 데이터 모델 (계획서 섹션 6.3.1)
struct DailyFocusTotal: Identifiable {
    let id = UUID()
    let date: Date
    let totalDuration: TimeInterval
}

struct LogView: View {
    // 섹션 6.2.2의 계획에 따라 @Query를 사용하여 모든 로그를 최신순으로 가져옵니다.[1]
    @Query(sort: \FocusLogEntry.startTime, order:.reverse) var logs: [FocusLogEntry]
    
    // 섹션 6.3.1의 핵심 요구사항: 시각화를 위한 데이터 집계 로직.[1]
    // [FocusLogEntry]를로 변환합니다.
    private var dailyTotals: {
        // Dictionary를 사용하여 날짜별로 로그를 그룹화합니다.
        let groupedByDay = Dictionary(grouping: logs) { log in
            Calendar.current.startOfDay(for: log.startTime)
        }
        
        // 그룹화된 데이터를 합산하여 DailyFocusTotal 배열로 변환합니다.
        return groupedByDay.map { (date, logsOnDate) -> DailyFocusTotal in
            let totalDuration = logsOnDate.reduce(0) { $0 + $1.duration }
            return DailyFocusTotal(date: date, totalDuration: totalDuration)
        }.sorted { $0.date > $1.date } // 최신 날짜가 먼저 오도록 정렬
    }

    var body: some View {
        NavigationView {
            VStack {
                // --- 차트 뷰 ---
                LogChartView(dailyTotals: dailyTotals)
                  .frame(height: 250)
                
                Divider()
                
                // --- 로그 목록 뷰 ---
                Text("집중 기록")
                  .font(.headline)
                  .padding(.top)
                
                if logs.isEmpty {
                    VStack {
                        Spacer()
                        Text("아직 기록된 집중 세션이 없습니다.")
                          .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(logs) { log in
                            HStack {
                                Text(log.startTime, style:.date)
                                Text(log.startTime, style:.time)
                                Spacer()
                                Text("\(Int(log.duration / 60))분")
                                  .fontWeight(.bold)
                            }
                        }
                    }
                  .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
          .navigationTitle("나의 생산성 기록")
        }
      .frame(minWidth: 400, minHeight: 500)
    }
}

struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        // 미리보기용으로 SwiftData 컨테이너를 설정해야 합니다.
        LogView()
          .modelContainer(for: FocusLogEntry.self, inMemory: true)
    }
}
