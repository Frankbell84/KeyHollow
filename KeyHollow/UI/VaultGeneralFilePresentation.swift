import Foundation
import SwiftUI
import UIKit
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

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try capability.sealScopedData(plaintext, domain: purpose.cryptographicDomain)
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try capability.openScopedData(ciphertext, domain: purpose.cryptographicDomain)
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

struct VaultGeneralFileTileView: View {
    let record: VaultGeneralFileRecord
    let thumbnail: UIImage?
    let selectionState: Bool?
    let openFileManager: () -> Void
    let toggleSelection: () -> Void

    private var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(record.originalByteCount),
            countStyle: .file
        )
    }

    var body: some View {
        Button {
            if selectionState == nil {
                openFileManager()
            } else {
                toggleSelection()
            }
        } label: {
            GeometryReader { proxy in
                VaultGalleryTileSurface(
                    title: record.displayName,
                    detail: formattedSize
                ) {
                    ZStack(alignment: .topTrailing) {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: GeneralFilePresentation.iconName(
                                for: record.contentTypeIdentifier
                            ))
                            .font(.system(size: 38, weight: .regular))
                            .foregroundStyle(.tint)
                        }

                        if let isSelected = selectionState {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(
                                    isSelected ? Color.accentColor : Color.white,
                                    Color.white
                                )
                                .padding(8)
                                .shadow(radius: 2)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(record.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            selectionState == nil
                ? "Opens encrypted vault files"
                : "Toggles selection for this file"
        )
    }

    private var accessibilityValue: String {
        let metadata = "Encrypted file, \(formattedSize)"
        guard let isSelected = selectionState else { return metadata }
        return "\(isSelected ? "Selected" : "Not selected"), \(metadata)"
    }
}
