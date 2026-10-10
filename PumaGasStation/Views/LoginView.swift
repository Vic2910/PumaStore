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
                    TextField("Correo electrónico", text: $usuario).keyboardType(.emailAddress)
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

                NavigationLink("Acceso con Supabase", destination: DatabaseConnectionView())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Acceso seguro con Supabase")
                        .font(.caption.bold())
                    Text("Usa el correo y contraseña de tu cuenta registrada.")
                    Text("Los datos se comparten entre móvil y web.")
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
