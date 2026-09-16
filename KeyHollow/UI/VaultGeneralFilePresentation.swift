import Foundation
import SwiftUI
import UniformTypeIdentifiers
import KeyHollowGeneralFileSupportAddOn

final class SessionGeneralFileAccess: VaultGeneralFileCryptographicAccess,
    @unchecked Sendable {
    let vaultID: UUID
    private let capability: VaultAccessCapability

    init(capability: VaultAccessCapability) {
        vaultID = capability.vaultID
        self.capability = capability
    }

    func checkAccess() throws {
        try capability.checkAccess()
    }

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try capability.sealScopedData(plaintext, domain: purpose.cryptographicDomain)
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try capability.openScopedData(ciphertext, domain: purpose.cryptographicDomain)
    }

    func open(
        _ ciphertext: Data,
        for purpose: VaultGeneralFileKeyPurpose,
        consuming consumer: (Data) throws -> Void
    ) throws {
        try capability.consumeOpenedScopedData(
            ciphertext,
            domain: purpose.cryptographicDomain,
            consumer
        )
    }
}

enum VaultContentAvailability {
    static func isEmpty(photoCount: Int, generalFileCount: Int) -> Bool {
        photoCount == 0 && generalFileCount == 0
    }
}

enum GeneralFilePresentation {
    static func iconName(for identifier: String?) -> String {
        guard let identifier,
              let type = UTType(identifier) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .movie) { return "video" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}

enum GeneralFileImportPresentation {
    static func message(for result: VaultGeneralFileImportResult) -> String {
        if result.importedCount > 0 {
            let noun = result.importedCount == 1 ? "file" : "files"
            if result.failedCount > 0 {
                return "Encrypted \(result.importedCount) \(noun) into this vault. \(result.failedCount) selected items were not supported or could not be read. The originals were kept."
            }
            return "Encrypted \(result.importedCount) \(noun) into this vault. The originals were kept."
        }
        return "No files were imported. Choose regular files up to 100 MB; vault backups, folders, apps, and executable files are excluded."
    }
}

struct GeneralFileImportProgressState: Equatable, Sendable {
    let total: Int
    private(set) var completed = 0
    private(set) var importedCount = 0
    private(set) var failedCount = 0

    init(total: Int) {
        self.total = max(0, total)
    }

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var statusText: String {
        guard total > 0 else { return "Preparing files" }
        if completed == total {
            let noun = total == 1 ? "file" : "files"
            return "Encrypted \(completed) of \(total) \(noun)"
        }
        return "Encrypting file \(completed + 1) of \(total)"
    }

    mutating func advance(succeeded: Bool) {
        guard completed < total else { return }
        completed += 1
        if succeeded {
            importedCount += 1
        } else {
            failedCount += 1
        }
    }

    var result: VaultGeneralFileImportResult {
        VaultGeneralFileImportResult(
            importedCount: importedCount,
            failedCount: failedCount
        )
    }
}

@MainActor
enum GeneralFileImportCoordinator {
    static func importFiles(
        at urls: [URL],
        using store: VaultGeneralFileStore,
        progressDidChange: (GeneralFileImportProgressState) -> Void
    ) async throws -> VaultGeneralFileImportResult {
        guard urls.count <= VaultGeneralFileStore.maximumBatchCount else {
            throw VaultGeneralFileStore.StoreError.batchTooLarge
        }

        var progress = GeneralFileImportProgressState(total: urls.count)
        progressDidChange(progress)
        for url in urls {
            try Task.checkCancellation()
            do {
                _ = try await store.importFile(at: url)
                progress.advance(succeeded: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                progress.advance(succeeded: false)
            }
            progressDidChange(progress)
        }
        return progress.result
    }
}

struct GeneralFileImportProgressView: View {
    let progress: GeneralFileImportProgressState

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    if progress.completed < progress.total {
                        ProgressView()
                    }
                    Text(progress.statusText)
                        .font(.headline)
                }
                ProgressView(value: progress.fractionCompleted, total: 1)
                    .frame(width: 230)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Importing files")
        .accessibilityValue(progress.statusText)
    }
}
