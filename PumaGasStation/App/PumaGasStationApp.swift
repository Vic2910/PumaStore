//
//  PumaGasStationApp.swift
//  PumaGasStation
//
//  Punto de entrada de la aplicación.
//

import SwiftUI

@main
struct PumaGasStationApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
        }
    }
}
