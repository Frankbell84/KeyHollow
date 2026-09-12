import Foundation
import KeyHollowBackupVerificationAddOn
import KeyHollowFileRecognitionAddOn
import KeyHollowTransferCore
import KeyHollowVaultCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// App-owned coordination for authenticating a portable backup without ever
/// creating a vault, retaining recovered key material, or exposing transfer
/// staging to the presentation add-on.
struct BackupVerificationCenterView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedArchive: StagedVaultFile?
    @State private var recoveryCode = ""
    @State private var report: BackupVerificationReport?
    @State private var filePickerRequest: BackupVerificationPickerRequest?
    @State private var activePickerRequestID: UUID?
    @State private var systemInteractionOpen = false
    @State private var isWorking = false
    @State private var isDismissing = false
    @State private var workingDescription = ""
    @State private var operationProgress: VaultTransferProgressDisplay?
    @State private var message: String?
    @State private var protectedTaskID: UUID?
    @State private var activeOperationID: UUID?
    @FocusState private var recoveryCodeFocused: Bool
    @AccessibilityFocusState private var messageFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    BackupVerificationReportView(report: report)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { cancelAndDismiss() }
                            }
                        }
                } else {
                    verificationForm
                }
            }
        }
        .sheet(item: $filePickerRequest, onDismiss: filePickerDidDismiss) { request in
            BackupVerificationDocumentImporter { url in
                finishFileSelection(url, requestID: request.id)
            }
        }
        .onChange(of: session.securityEpoch) { _, _ in
            invalidateFilePicker()
            let protectedTaskWasActive = cancelVerification()
            finishSystemInteractionIfNeeded()
            clearSensitiveState()
            if protectedTaskWasActive {
                selectedArchive = nil
            } else {
                discardSelectedArchive()
            }
            report = nil
            publishMessage("Verification canceled because KeyHollow locked.")
        }
        .onDisappear {
            invalidateFilePicker()
            let protectedTaskWasActive = cancelVerification()
            finishSystemInteractionIfNeeded()
            clearSensitiveState()
            if protectedTaskWasActive {
                selectedArchive = nil
            } else {
                discardSelectedArchive()
            }
        }
    }

    private var verificationForm: some View {
        Form {
            Section {
                Text("Check a .khvault backup before you need it. KeyHollow authenticates the archive and checks its supported encrypted contents under the archive format's current compatibility rules. Temporary verification material is deleted, and the backup is not installed or changed.")
                    .foregroundStyle(.secondary)
            }

            Section("1. Choose encrypted backup") {
                Button(selectedArchive == nil ? "Choose .khvault File" : "Choose a Different File") {
                    beginFileSelection()
                }
                .disabled(isWorking)
                .accessibilityIdentifier("backup-verification-choose-file")

                if let selectedArchive {
                    LabeledContent("Selected", value: selectedArchive.displayName)
                    LabeledContent(
                        "Size",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(selectedArchive.byteCount),
                            countStyle: .file
                        )
                    )
                }
            }

            Section("2. Authenticate and verify") {
                TextField("Recovery code", text: $recoveryCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .privacySensitive()
                    .submitLabel(.done)
                    .focused($recoveryCodeFocused)
                    .onSubmit { dismissKeyboard() }
                    .onChange(of: recoveryCode) { _, value in
                        recoveryCode = Self.sanitizeRecoveryCode(value)
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("backup-verification-recovery-code")

                Button("Verify Backup") {
                    dismissKeyboard()
                    verifyBackup()
                }
                .frame(maxWidth: .infinity)
                .disabled(!canVerify || isWorking)
                .accessibilityIdentifier("backup-verification-run")
            }

            Section {
                Text("Current portable backups preserve photos and general files, including videos imported through Files. Folder names and folder membership are not included in this archive format.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .accessibilityFocused($messageFocused)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Verify Backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { cancelAndDismiss() }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .overlay {
            if isWorking {
                if let operationProgress {
                    VaultTransferProgressView(display: operationProgress)
                } else {
                    ProgressView(workingDescription)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .interactiveDismissDisabled(isWorking || isDismissing)
    }

    private var canVerify: Bool {
        selectedArchive != nil
            && (try? PortableArchiveRecoveryCode.canonicalize(recoveryCode)) != nil
    }

    private func beginFileSelection() {
        guard !isWorking, activePickerRequestID == nil else { return }
        dismissKeyboard()
        recoveryCode = ""
        message = nil
        messageFocused = false
        let request = BackupVerificationPickerRequest()
        activePickerRequestID = request.id
        systemInteractionOpen = true
        session.beginSystemInteraction()
        filePickerRequest = request
    }

    private func finishFileSelection(_ url: URL?, requestID: UUID) {
        guard activePickerRequestID == requestID else { return }
        activePickerRequestID = nil
        filePickerRequest = nil
        finishSystemInteractionIfNeeded()

        guard let url else {
            publishMessage("File selection canceled.")
            return
        }

        stageSelectedArchive(from: url)
    }

    private func filePickerDidDismiss() {
        finishSystemInteractionIfNeeded()
        guard activePickerRequestID != nil else { return }
        activePickerRequestID = nil
        filePickerRequest = nil
        publishMessage("File selection canceled.")
    }

    private func invalidateFilePicker() {
        activePickerRequestID = nil
        filePickerRequest = nil
    }

    private func stageSelectedArchive(from url: URL) {
        do {
            try discardSelectedArchiveChecked()
        } catch {
            publishMessage(
                "KeyHollow could not remove the previous protected temporary copy. Lock or restart the app before choosing another backup."
            )
            return
        }
        let operationID = UUID()
        activeOperationID = operationID
        isWorking = true
        workingDescription = "Copying backup into protected storage..."
        operationProgress = VaultTransferProgressDisplay(
            title: "Loading encrypted vault…",
            fractionCompleted: nil,
            detail: nil
        )
        message = nil
        messageFocused = false

        protectedTaskID = session.startProtectedTask {
            var newlyStagedArchive: StagedVaultFile?
            do {
                guard let stagedArchive = try await Self.stageArchiveOffMain(
                    url,
                    progress: { progress in
                        Task { @MainActor in
                            guard activeOperationID == operationID else { return }
                            operationProgress = .copying(progress)
                        }
                    }
                ) else {
                    throw VaultFileIngressError.unsupportedFile
                }
                newlyStagedArchive = stagedArchive
                try Task.checkCancellation()
                guard activeOperationID == operationID else {
                    try stagedArchive.discardChecked()
                    return
                }
                selectedArchive = stagedArchive
                newlyStagedArchive = nil
                recoveryCode = ""
                message = nil
                recoveryCodeFocused = true
                finishProtectedOperation(operationID: operationID)
            } catch is CancellationError {
                let cleanupSucceeded = newlyStagedArchive.map(Self.discardChecked) ?? true
                guard activeOperationID == operationID else { return }
                if !cleanupSucceeded {
                    selectedArchive = newlyStagedArchive
                    publishMessage(
                        "The backup copy was canceled, but protected temporary data could not be removed. Lock or restart KeyHollow before trying again."
                    )
                }
                finishProtectedOperation(operationID: operationID)
            } catch VaultFileIngressError.unsupportedFile {
                let cleanupSucceeded = newlyStagedArchive.map(Self.discardChecked) ?? true
                guard activeOperationID == operationID else { return }
                if cleanupSucceeded {
                    publishMessage("Choose a KeyHollow .khvault file.")
                } else {
                    selectedArchive = newlyStagedArchive
                    publishMessage(
                        "The selected item was not a supported backup, and its protected temporary copy could not be removed. Lock or restart KeyHollow before trying again."
                    )
                }
                finishProtectedOperation(operationID: operationID)
            } catch VaultFileIngressError.insufficientStorage {
                let cleanupSucceeded = newlyStagedArchive.map(Self.discardChecked) ?? true
                guard activeOperationID == operationID else { return }
                if cleanupSucceeded {
                    publishMessage(
                        "This iPhone does not have enough free space to verify that backup safely."
                    )
                } else {
                    selectedArchive = newlyStagedArchive
                    publishMessage(
                        "The backup could not be copied safely, and protected temporary data could not be removed. Lock or restart KeyHollow before trying again."
                    )
                }
                finishProtectedOperation(operationID: operationID)
            } catch {
                let cleanupSucceeded = newlyStagedArchive.map(Self.discardChecked) ?? true
                guard activeOperationID == operationID else { return }
                if cleanupSucceeded {
                    publishMessage(
                        "The selected backup could not be copied into protected temporary storage."
                    )
                } else {
                    selectedArchive = newlyStagedArchive
                    publishMessage(
                        "The backup copy failed, and protected temporary data could not be removed. Lock or restart KeyHollow before trying again."
                    )
                }
                finishProtectedOperation(operationID: operationID)
            }
        }
    }

    private static func stageArchiveOffMain(
        _ url: URL,
        progress: @escaping @Sendable (VaultFileIngressProgress) -> Void
    ) async throws -> StagedVaultFile? {
        let task = Task.detached(priority: .userInitiated) {
            let staged = try KHVaultFileIngress().stageIfRecognized(
                url,
                progress: progress
            )
            do {
                try Task.checkCancellation()
                return staged
            } catch {
                try staged?.discardChecked()
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func verifyBackup() {
        guard canVerify,
              let selectedArchive,
              !isWorking else { return }

        let credential = PortableArchiveCredential.recoveryCode(recoveryCode)
        let operationID = UUID()
        activeOperationID = operationID
        recoveryCode = ""
        isWorking = true
        workingDescription = "Authenticating every file..."
        operationProgress = VaultTransferProgressDisplay(
            title: "Preparing secure verification…",
            fractionCompleted: nil,
            detail: nil
        )
        message = nil
        messageFocused = false

        protectedTaskID = session.startProtectedTask {
            do {
                let verified = try await EncryptedVaultTransferCoordinator().verifyArchive(
                    archiveURL: selectedArchive.url,
                    credential: credential,
                    supplementalContent: GeneralFilePortableTransferBridge(),
                    progress: { progress in
                        Task { @MainActor in
                            if activeOperationID == operationID {
                                operationProgress = .validating(progress)
                            }
                        }
                    }
                )
                try Task.checkCancellation()

                let sanitizedReport = BackupVerificationReport(
                    displayName: selectedArchive.displayName,
                    archiveByteCount: selectedArchive.byteCount,
                    sourceVaultCreatedAt: verified.sourceVaultCreatedAt,
                    verifiedAt: Date(),
                    catalogVersion: verified.catalogVersion,
                    photoCount: verified.authenticatedPhotoCount,
                    generalFileCount: verified.authenticatedFileCount,
                    authenticatedEntryCount: verified.authenticatedEntryCount,
                    legacyOversizedPhotoCount: verified.legacyOversizedPhotoCount
                )
                do {
                    try selectedArchive.discardChecked()
                } catch {
                    throw BackupVerificationCoordinatorError.ingressCleanupFailed
                }
                try Task.checkCancellation()

                guard activeOperationID == operationID,
                      !Task.isCancelled else { return }
                self.selectedArchive = nil
                report = sanitizedReport
                finishProtectedOperation(operationID: operationID)
            } catch is CancellationError {
                let cleanupSucceeded = Self.discardChecked(selectedArchive)
                guard activeOperationID == operationID else { return }
                if cleanupSucceeded {
                    self.selectedArchive = nil
                } else {
                    publishMessage(
                        "Verification was canceled, but protected temporary data could not be removed. Lock or restart KeyHollow before trying again."
                    )
                }
                finishProtectedOperation(operationID: operationID)
            } catch BackupVerificationCoordinatorError.ingressCleanupFailed {
                let cleanupSucceeded = Self.discardChecked(selectedArchive)
                guard activeOperationID == operationID else { return }
                if cleanupSucceeded {
                    self.selectedArchive = nil
                }
                publishMessage(
                    "Verification did not finish safely because protected temporary data could not be removed. No success was recorded. Lock or restart KeyHollow before trying again."
                )
                finishProtectedOperation(operationID: operationID)
            } catch EncryptedVaultTransferError.archiveCleanupFailed {
                let ingressCleanupSucceeded = Self.discardChecked(selectedArchive)
                guard activeOperationID == operationID else { return }
                if ingressCleanupSucceeded {
                    self.selectedArchive = nil
                }
                publishMessage(
                    "Verification did not finish safely because protected temporary data could not be removed. No success was recorded. Lock or restart KeyHollow before trying again."
                )
                finishProtectedOperation(operationID: operationID)
            } catch {
                let cleanupSucceeded = Self.discardChecked(selectedArchive)
                guard activeOperationID == operationID else { return }
                if cleanupSucceeded {
                    self.selectedArchive = nil
                    publishMessage(
                        "The backup could not be verified. The recovery code may be incorrect, or the file may be damaged, unsupported, or unavailable. No vault was installed or changed."
                    )
                } else {
                    publishMessage(
                        "The backup was not verified, and protected temporary data could not be removed. Lock or restart KeyHollow before trying again."
                    )
                }
                finishProtectedOperation(operationID: operationID)
            }
        }
    }

    private func finishProtectedOperation(operationID: UUID) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        protectedTaskID = nil
        isWorking = false
        workingDescription = ""
        operationProgress = nil
        recoveryCode = ""
    }

    @discardableResult
    private func cancelVerification() -> Bool {
        let protectedTaskWasActive = protectedTaskID != nil
        activeOperationID = nil
        if let protectedTaskID {
            session.cancelSensitiveTask(protectedTaskID)
        }
        protectedTaskID = nil
        isWorking = false
        operationProgress = nil
        workingDescription = ""
        return protectedTaskWasActive
    }

    private func finishSystemInteractionIfNeeded() {
        guard systemInteractionOpen else { return }
        systemInteractionOpen = false
        session.endSystemInteraction()
    }

    private func cancelAndDismiss() {
        guard !isDismissing else { return }
        dismissKeyboard()
        isDismissing = true
        workingDescription = "Finishing secure cleanup..."
        isWorking = protectedTaskID != nil
        activeOperationID = nil
        let taskID = protectedTaskID
        protectedTaskID = nil
        invalidateFilePicker()
        finishSystemInteractionIfNeeded()
        clearSensitiveState()
        Task { @MainActor in
            if let taskID {
                await session.cancelSensitiveTaskAndWait(taskID)
            }
            do {
                try discardSelectedArchiveChecked()
                isWorking = false
                workingDescription = ""
                dismiss()
            } catch {
                isDismissing = false
                isWorking = false
                workingDescription = ""
                publishMessage(
                    "KeyHollow could not finish removing protected temporary data. Lock or restart the app before trying again."
                )
            }
        }
    }

    private func clearSensitiveState() {
        recoveryCode = ""
        recoveryCodeFocused = false
    }

    private func discardSelectedArchive() {
        guard let archive = selectedArchive else { return }
        do {
            try archive.discardChecked()
            if selectedArchive == archive {
                selectedArchive = nil
            }
        } catch {
            archive.discard()
        }
    }

    private func discardSelectedArchiveChecked() throws {
        guard let archive = selectedArchive else { return }
        try archive.discardChecked()
        if selectedArchive == archive {
            selectedArchive = nil
        }
    }

    private func publishMessage(_ value: String) {
        message = value
        messageFocused = true
    }

    private func dismissKeyboard() {
        recoveryCodeFocused = false
        KeyboardDismissal.dismiss()
    }

    private static func sanitizeRecoveryCode(_ value: String) -> String {
        let allowed = value.uppercased().filter { character in
            character == "-" || character.isLetter || character.isNumber
        }
        return String(allowed.prefix(39))
    }

    private static func discardChecked(_ archive: StagedVaultFile) -> Bool {
        do {
            try archive.discardChecked()
            return true
        } catch {
            archive.discard()
            return false
        }
    }
}

private struct BackupVerificationPickerRequest: Identifiable {
    let id = UUID()
}

private enum BackupVerificationCoordinatorError: Error {
    case ingressCleanupFailed
}

private struct BackupVerificationDocumentImporter: UIViewControllerRepresentable {
    let onComplete: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let type = UTType(
            exportedAs: "com.keyhollow.encrypted-vault",
            conformingTo: .data
        )
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [type],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (URL?) -> Void
        private var completed = false

        init(onComplete: @escaping (URL?) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            finish(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(nil)
        }

        private func finish(_ url: URL?) {
            guard !completed else { return }
            completed = true
            onComplete(url)
        }
    }
}
