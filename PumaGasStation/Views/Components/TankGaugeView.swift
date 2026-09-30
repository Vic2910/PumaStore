import SwiftUI
struct TankGaugeView: View {
    let title: String
    let percentage: Double
    let status: TankStatus
    let subtitle: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.bold())
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4).fill(PumaStyle.background)
                Rectangle().fill(status.color).frame(height: 66 * percentage)
            }.frame(width: 36, height: 66).clipShape(RoundedRectangle(cornerRadius: 4))
            Text("\(Int(percentage * 100))%").font(.caption.bold())
            Text(status.rawValue).font(.caption2).foregroundStyle(status.color)
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}

extension TankStatus {
    var color: Color {
        switch self {
        case .óptimo: return PumaStyle.green
        case .medio: return PumaStyle.yellow
        case .crítico: return .red
        }
    }
}
