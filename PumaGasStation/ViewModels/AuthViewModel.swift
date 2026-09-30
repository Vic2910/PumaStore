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
        if let storageError = dataService.storageError { errorMessage = storageError; return }
        if let user = dataService.authenticate(usuario: usuario, password: password) {
            errorMessage = nil
            currentUser = user
        } else {
            errorMessage = "Usuario o contraseña incorrectos."
        }
    }

    init() {
        dataService.$users.sink { [weak self] users in
            guard let self, let current = self.currentUser else { return }
            self.currentUser = users.first { $0.id == current.id }
        }.store(in: &cancellables)
    }
    private var cancellables = Set<AnyCancellable>()
    func logout() {
        currentUser = nil
    }
}
