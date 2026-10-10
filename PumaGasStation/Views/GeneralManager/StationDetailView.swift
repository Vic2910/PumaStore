//
//  StationDetailView.swift
//  PumaGasStation
//
//  Vista detallada de una estación específica para el Gerente General.
//

import SwiftUI

struct StationDetailView: View {
    @EnvironmentObject var viewModel: GeneralManagerViewModel
    let station: Station
    private var current: Station { viewModel.stations.first { $0.id == station.id } ?? station }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.nombre).font(.title2.bold())
                    Text(current.direccion).font(.subheadline).foregroundStyle(.secondary)
                    Text("Gerente: \(current.gerenteNombre)").font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    MetricCardView(title: "Ventas", value: "$" + String(format: "%.2f", current.totalVentasMonto), color: .green, icon: "dollarsign.circle.fill")
                    MetricCardView(title: "Compras", value: "$" + String(format: "%.2f", current.totalComprasMonto), color: .blue, icon: "shippingbox.fill")
                }
                MetricCardView(title: "Pérdidas (gal)", value: String(format: "%.1f", current.totalPerdidasGalones), color: .red, icon: "drop.triangle.fill")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Niveles de Tanques").font(.headline)
                    HStack {
                        ForEach(current.tanks) { tank in
                            TankGaugeView(
                                title: tank.fuelType.rawValue,
                                percentage: tank.percentage,
                                status: tank.status,
                                subtitle: "\(Int(tank.currentGallons))/\(Int(tank.capacityGallons)) gal"
                            )
                        }
                    }
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Historial de Cortes").font(.headline)
                    if current.cuts.isEmpty {
                        Text("Sin cortes registrados todavía.").foregroundStyle(.secondary)
                    }
                    ForEach(current.cuts.sorted(by: { $0.fecha > $1.fecha })) { cut in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cut.shift.rawValue).font(.subheadline.bold())
                                Text(cut.fecha.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(cut.cerrado ? "Cerrado" : "Abierto")
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(cut.cerrado ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundStyle(cut.cerrado ? .green : .orange)
                                .clipShape(Capsule())
                            Text("$" + String(format: "%.0f", cut.totalVentasMonto))
                                .font(.subheadline.bold())
                        }
                        .padding()
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
        .pumaPage()
        .navigationTitle(current.nombre)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        StationDetailView(station: Station(nombre: "Sucursal de vista previa", direccion: "", ciudad: "", tanks: [], gerenteNombre: "")).environmentObject(GeneralManagerViewModel())
    }
}
