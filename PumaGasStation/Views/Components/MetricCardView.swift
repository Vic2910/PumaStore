import SwiftUI

enum PumaStyle {
    static let green = Color(red: 0, green: 0.67, blue: 0.31)
    static let background = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let yellow = Color(red: 1, green: 0.78, blue: 0)
    static func money(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
}
extension View {
    func pumaCard() -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    func pumaPage() -> some View { background(PumaStyle.background).tint(PumaStyle.green) }
}
struct MetricCardView: View {
    let title: String
    let value: String
    var color: Color = .primary
    var icon: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.caption)
                Spacer(minLength: 0)
                if let icon { Image(systemName: icon).foregroundStyle(color).padding(6).background(PumaStyle.background).clipShape(Circle()) }
            }
            Text(value).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
        }.pumaCard().overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.7), lineWidth: 1))
    }
}
struct CriticalAlertBanner: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.red).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
struct BrandHeader: View {
    let name: String
    let role: String
    var body: some View {
        HStack {
            Image("PumaLogo").resizable().interpolation(.high).frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased()).font(.caption.bold()).foregroundStyle(PumaStyle.green)
                Text(role).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "bell.badge").font(.title3)
            Text("👩🏻‍🦰").font(.title2)
        }
    }
}
struct ProfileView: View {
    @EnvironmentObject var auth: AuthViewModel
    var body: some View {
        Form {
            if let user = auth.currentUser {
                Section("Perfil") { Text(user.nombre); Text(user.role.rawValue); Text(user.usuario) }
            }
            Section { Button("Cerrar sesión", role: .destructive) { auth.logout() } }
        }.navigationTitle("Perfil")
    }
}

extension FuelType {
    /// Color corporativo asociado a cada tipo de combustible (paleta PUMA).
    var color: Color {
        switch self {
        case .súper: return PumaStyle.green
        case .regular: return PumaStyle.yellow
        case .diésel: return .red
        }
    }

    var icon: String {
        switch self {
        case .súper: return "fuelpump.fill"
        case .regular: return "fuelpump"
        case .diésel: return "fuelpump.circle.fill"
        }
    }
}
