import SwiftUI
import Charts

struct LogChartView: View {
    let dailyTotals:

    var body: some View {
        VStack(alignment:.leading) {
            Text("일별 집중 시간")
              .font(.title2)
              .padding(.leading)
            
            // 섹션 6.3.2의 계획에 따른 SwiftUI Charts 구현 [1]
            Chart(dailyTotals) { dailyData in
                // 각 날짜별 총 집중 시간을 막대 그래프로 표시
                BarMark(
                    x:.value("날짜", dailyData.date, unit:.day),
                    y:.value("집중 시간(분)", dailyData.totalDuration / 60)
                )
              .foregroundStyle(by:.value("날짜", dailyData.date.formatted(date:.abbreviated, time:.omitted)))
              .cornerRadius(6)
            }
            // X축 설정: 날짜를 요일로 표시
          .chartXAxis {
                AxisMarks(values:.stride(by:.day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format:.dateTime.weekday(.narrow), centered: true)
                }
            }
            // Y축 설정: 분 단위로 레이블 표시
          .chartYAxis {
                AxisMarks(position:.leading) { value in
                    AxisGridLine()
                    AxisValueLabel("\(value.as(Int.self)?? 0) 분")
                }
            }
          .chartLegend(.hidden) // 범례는 막대 색상으로 충분하므로 숨김
          .padding()
        }
    }
}
