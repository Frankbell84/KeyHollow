import SwiftUI
import UIKit
import KeyHollowVaultCore

struct VaultSecuritySettingsView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService

    @State private var showingChangePasscode = false
    @State private var showingDeleteVault = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Change This Vault Passcode") {
                        showingChangePasscode = true
                    }

                    Button("Delete This Vault", role: .destructive) {
                        showingDeleteVault = true
                    }
                } footer: {
                    Text("These controls affect only the vault that is currently open. KeyHollow does not display other vaults or how many exist.")
                }
            }
            .navigationTitle("Vault Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingChangePasscode) {
                ChangeVaultPasscodeView(service: service)
                    .environmentObject(session)
            }
            .sheet(isPresented: $showingDeleteVault) {
                DeleteCurrentVaultView(service: service) {
                    dismiss()
                }
                .environmentObject(session)
            }
        }
    }
}

private struct ChangeVaultPasscodeView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService

    @State private var currentPasscode = ""
    @State private var tier: PasscodeTier = .enhanced
    @State private var customLength = 10
    @State private var newPasscode = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var isWorking = false

    private var requiredLength: Int { tier.fixedLength ?? customLength }

    var body: some View {
        NavigationStack {
            Form {
                Section("Verify current passcode") {
                    SecureField("Current passcode", text: $currentPasscode)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .onChange(of: currentPasscode) { _, value in
                            currentPasscode = sanitize(value, limit: PasscodePolicy.maximumLength)
                        }
                }

                Section("New security level") {
                    Picker("Level", selection: $tier) {
                        ForEach(PasscodeTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }

                    if tier == .custom {
                        Stepper(
                            "Length: \(customLength) digits",
                            value: $customLength,
                            in: PasscodePolicy.minimumLength...PasscodePolicy.maximumLength
                        )
                    } else {
                        LabeledContent("Passcode length", value: "\(requiredLength) digits")
                    }
                }

                Section("New passcode") {
                    SecureField("Enter \(requiredLength)-digit passcode", text: $newPasscode)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .onChange(of: newPasscode) { _, value in
                            newPasscode = sanitize(value, limit: requiredLength)
                        }

                    SecureField("Confirm new passcode", text: $confirmation)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .onChange(of: confirmation) { _, value in
                            confirmation = sanitize(value, limit: requiredLength)
                        }

                    Text("Avoid birthdays, phone numbers, repeated digits, counting sequences, and repeated patterns.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let rejectionMessage {
                        Text(rejectionMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                Section {
                    Button("Change Passcode") { changePasscode() }
                        .frame(maxWidth: .infinity)
                        .disabled(!canSubmit || isWorking)
                }
            }
            .navigationTitle("Change Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
        .onChange(of: session.securityEpoch) { _, _ in
            currentPasscode = ""
            newPasscode = ""
            confirmation = ""
            message = nil
            isWorking = false
        }
    }

    private var canSubmit: Bool {
        PasscodePolicy.isValidForUnlock(currentPasscode) &&
        newPasscode.count == requiredLength &&
        newPasscode == confirmation &&
        PasscodePolicy.isAcceptableNewPasscode(
            newPasscode,
            tier: tier,
            customLength: tier == .custom ? customLength : nil
        )
    }

    private var rejectionMessage: String? {
        guard newPasscode.count == requiredLength else { return nil }
        return PasscodePolicy.rejectionReason(forNewPasscode: newPasscode)?.message
    }

    private func changePasscode() {
        guard canSubmit,
              let vaultID = session.activeVaultID,
              !isWorking else { return }

        let old = currentPasscode
        let new = newPasscode
        currentPasscode = ""
        newPasscode = ""
        confirmation = ""
        message = nil
        isWorking = true
        let unlockAuthorization = session.authorizeUnlockCompletion()
        let requestSecurityEpoch = session.securityEpoch
        session.startProtectedTask {
            do {
                let unlocked = try await service.changePasscode(
                    currentPasscode: old,
                    newPasscode: new,
                    expectedVaultID: vaultID
                )
                let accepted = session.completeUnlock(
                    vaultID: unlocked.vaultID,
                    key: unlocked.vaultKey,
                    authorization: unlockAuthorization
                )
                guard accepted else { return }
                isWorking = false
                dismiss()
            } catch VaultUnlockError.passcodeAlreadyUsed {
                guard session.securityEpoch == requestSecurityEpoch else { return }
                message = "That new passcode cannot be used. Choose a different passcode."
                isWorking = false
            } catch VaultUnlockError.invalidCredentials {
                guard session.securityEpoch == requestSecurityEpoch else { return }
                message = "The current passcode was not recognized for this vault."
                isWorking = false
            } catch {
                guard session.securityEpoch == requestSecurityEpoch else { return }
                message = "The passcode change could not be verified. Keep both passcodes available and restart KeyHollow before trying again."
                isWorking = false
            }
        }
    }

    private func sanitize(_ value: String, limit: Int) -> String {
        String(value.filter(\.isNumber).prefix(limit))
    }
}

private struct DeleteCurrentVaultView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService
    let onDeleted: () -> Void

    @State private var currentPasscode = ""
    @State private var confirmationText = ""
    @State private var message: String?
    @State private var isWorking = false
    @FocusState private var focusedField: DeleteVaultField?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        Text("Deleting this vault removes its KeyHollow credential envelope and its encrypted photo data. This action cannot be undone.")
                            .foregroundStyle(.secondary)
                    }

                    Section("Verify current passcode") {
                        SecureField("Current passcode", text: $currentPasscode)
                            .keyboardType(.numberPad)
                            .textContentType(.password)
                            .focused($focusedField, equals: .currentPasscode)
                            .onChange(of: currentPasscode) { _, value in
                                currentPasscode = String(value.filter(\.isNumber).prefix(PasscodePolicy.maximumLength))
                            }
                    }

                    Section("Confirm deletion") {
                        TextField("Type DELETE", text: $confirmationText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focusedField, equals: .confirmation)
                            .onSubmit {
                                finishDeleteKeyboardEntry(using: proxy)
                            }
                            .onChange(of: confirmationText) { _, value in
                                let normalized = String(
                                    value.uppercased().filter(\.isLetter).prefix(6)
                                )
                                if confirmationText != normalized {
                                    confirmationText = normalized
                                }
                                if normalized == "DELETE", focusedField == .confirmation {
                                    advanceToDeleteButton(using: proxy)
                                }
                            }
                    }
                    .id(DeleteVaultSection.confirmation)

                    if let message {
                        Section { Text(message).foregroundStyle(.secondary) }
                    }

                    Section {
                        Button("Permanently Delete This Vault", role: .destructive) {
                            focusedField = nil
                            KeyboardDismissal.dismiss()
                            deleteVault()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(!canDelete || isWorking)
                    }
                    .id(DeleteVaultSection.deleteButton)
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Delete Vault")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            focusedField = nil
                            KeyboardDismissal.dismiss()
                            dismiss()
                        }
                        .disabled(isWorking)
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(focusedField == .currentPasscode ? "Continue" : "Done") {
                            finishDeleteKeyboardEntry(using: proxy)
                        }
                    }
                }
                .interactiveDismissDisabled(isWorking)
            }
        }
        .onChange(of: session.securityEpoch) { _, _ in
            currentPasscode = ""
            confirmationText = ""
            message = nil
            isWorking = false
            focusedField = nil
        }
    }

    private var canDelete: Bool {
        PasscodePolicy.isValidForUnlock(currentPasscode) &&
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    private func finishDeleteKeyboardEntry(using proxy: ScrollViewProxy) {
        if focusedField == .currentPasscode {
            focusedField = .confirmation
            withAnimation {
                proxy.scrollTo(DeleteVaultSection.confirmation, anchor: .center)
            }
        } else {
            advanceToDeleteButton(using: proxy)
        }
    }

    private func advanceToDeleteButton(using proxy: ScrollViewProxy) {
        focusedField = nil
        KeyboardDismissal.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation {
                proxy.scrollTo(DeleteVaultSection.deleteButton, anchor: .center)
            }
        }
    }

    private func deleteVault() {
        guard canDelete,
              let vaultID = session.activeVaultID,
              !isWorking else { return }

        focusedField = nil
        KeyboardDismissal.dismiss()

        let passcode = currentPasscode
        currentPasscode = ""
        confirmationText = ""
        message = nil
        isWorking = true
        let requestSecurityEpoch = session.securityEpoch
        Task {
            do {
                try await VaultDeletionSessionCoordinator.deleteVault(
                    service: service,
                    session: session,
                    currentPasscode: passcode,
                    expectedVaultID: vaultID
                )
                isWorking = false
                dismiss()
                onDeleted()
            } catch VaultUnlockError.invalidCredentials {
                guard session.securityEpoch == requestSecurityEpoch else { return }
                message = "The current passcode was not recognized for this vault."
                isWorking = false
            } catch VaultUnlockError.credentialDestroyedCleanupIncomplete {
                // The credential deletion committed even though encrypted-file
                // cleanup was incomplete. Never leave its key live or invite a
                // retry with a LowKey that can no longer succeed.
                isWorking = false
                dismiss()
                onDeleted()
            } catch VaultUnlockError.credentialStateUnknown {
                // Fail closed without claiming deletion. Recovery must inspect
                // the authenticated journal before KeyHollow can know whether
                // the LowKey still exists.
                isWorking = false
                dismiss()
            } catch {
                guard session.securityEpoch == requestSecurityEpoch else {
                    // Authorization succeeded and the session was retired, but
                    // deletion did not report a committed outcome. Stay locked
                    // and let startup recovery recheck any authenticated journal.
                    isWorking = false
                    dismiss()
                    return
                }
                message = "KeyHollow could not complete vault deletion cleanly. Do not assume the operation succeeded until the vault state is rechecked."
                isWorking = false
            }
        }
    }
}

private enum DeleteVaultField: Hashable {
    case currentPasscode
    case confirmation
}

private enum DeleteVaultSection: Hashable {
    case confirmation
    case deleteButton
}

