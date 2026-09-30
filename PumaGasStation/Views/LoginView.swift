//
//  LoginView.swift
//  PumaGasStation
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var usuario: String = ""
    @State private var password: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "fuelpump.circle.fill")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .foregroundStyle(PumaStyle.green)

                    Text("PUMA Franquicia")
                        .font(.largeTitle.bold())
                    Text("Sistema de Gestión de Estaciones de Servicio")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    TextField("Usuario", text: $usuario)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    SecureField("Contraseña", text: $password)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        authViewModel.login(usuario: usuario, password: password)
                    } label: {
                        Text("Iniciar sesión")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(PumaStyle.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(usuario.isEmpty || password.isEmpty)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Usuarios de prueba (contraseña: 1234)")
                        .font(.caption.bold())
                    Text("• gerente.general — Gerente General")
                    Text("• santa.ana — Gerente de Sucursal (Santa Ana)")
                    Text("• san.salvador — Gerente de Sucursal (San Salvador)")
                    Text("• sonsonate — Gerente de Sucursal (Sonsonate)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
