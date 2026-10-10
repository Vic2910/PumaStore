//
//  AuthViewModel.swift
//  PumaGasStation
//

import Foundation
import Combine

final class AuthViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var errorMessage: String?

    private let dataService = MockDataService.shared

    func login(usuario: String, password: String) {
        Task { @MainActor in
            await SupabaseService.shared.login(email: usuario.trimmingCharacters(in: .whitespacesAndNewlines), password: password, auth: self)
            if currentUser == nil { errorMessage = SupabaseService.shared.message }
            else { errorMessage = nil }
        }
    }

    init() {
        dataService.$users.sink { [weak self] users in
            guard let self, let current = self.currentUser else { return }
            self.currentUser = users.first { $0.id == current.id && $0.isActive }
        }.store(in: &cancellables)
    }
    private var cancellables = Set<AnyCancellable>()
    func logout() {
        currentUser = nil
        Task { @MainActor in SupabaseService.shared.logout() }
    }
}
