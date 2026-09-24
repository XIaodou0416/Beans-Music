import SwiftUI

struct SMSLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MineViewModel

    @State private var countryCode = "86"
    @State private var phone = ""
    @State private var code = ""
    @State private var captchaKey = ""
    @State private var message = ""
    @State private var isSendingCode = false
    @State private var isLoggingIn = false
    @State private var cooldown = 0
    @State private var cooldownTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Text("+")
                            .foregroundStyle(.secondary)
                        TextField("86", text: $countryCode)
                            .keyboardType(.numberPad)
                            .textContentType(.telephoneNumber)
                            .frame(width: 58)
                        TextField("手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }

                    HStack(spacing: 12) {
                        TextField("验证码", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)

                        Button(action: sendCode) {
                            if isSendingCode {
                                ProgressView()
                            } else {
                                Text(cooldown > 0 ? "\(cooldown)s" : "获取验证码")
                            }
                        }
                        .disabled(!canSendCode)
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(message == "登录成功" ? .green : .secondary)
                    }
                }

                Section {
                    Button(action: login) {
                        if isLoggingIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("登录", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canLogin)
                }
            }
            .navigationTitle("短信验证码登录")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            cooldownTask?.cancel()
        }
    }

    private var normalizedPhone: String {
        phone.filter(\.isNumber)
    }

    private var normalizedCode: String {
        code.filter(\.isNumber)
    }

    private var canSendCode: Bool {
        !isSendingCode && !isLoggingIn && cooldown == 0 && !normalizedPhone.isEmpty
    }

    private var canLogin: Bool {
        !isSendingCode && !isLoggingIn && !captchaKey.isEmpty && !normalizedPhone.isEmpty && !normalizedCode.isEmpty
    }

    private func sendCode() {
        guard canSendCode else { return }
        isSendingCode = true
        message = ""
        Task {
            do {
                captchaKey = try await viewModel.sendAppSMSCode(
                    phone: normalizedPhone,
                    countryCode: countryCode
                )
                message = "验证码已发送"
                startCooldown()
            } catch {
                message = error.localizedDescription
            }
            isSendingCode = false
        }
    }

    private func login() {
        guard canLogin else { return }
        isLoggingIn = true
        message = ""
        Task {
            do {
                try await viewModel.completeAppSMSLogin(
                    phone: normalizedPhone,
                    countryCode: countryCode,
                    code: normalizedCode,
                    captchaKey: captchaKey
                )
                message = "登录成功"
                try? await Task.sleep(for: .milliseconds(800))
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isLoggingIn = false
        }
    }

    private func startCooldown() {
        cooldownTask?.cancel()
        cooldown = 60
        cooldownTask = Task { @MainActor in
            while cooldown > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    cooldown -= 1
                }
            }
        }
    }
}
