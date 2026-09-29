import SwiftUI

/// Presentation only: emits typed intent while the gallery owns operations.
struct VaultGalleryHeaderControls: View {
    enum Action {
        case cancelSelection, toggleSelectAll, lock, back, beginSelection
        case importContent, newFolder, newVault, importVault, exportVault
        case verifyBackup, vaultFiles, securitySettings
    }

    let isSelecting: Bool
    let isAtRoot: Bool
    let title: String
    let selectionCount: Int
    let allVisibleSelected: Bool
    let selectionUnavailable: Bool
    let importUnavailable: Bool
    let isWorking: Bool
    let perform: (Action) -> Void

    var body: some View {
        HStack(spacing: 18) {
            if isSelecting {
                Button("Cancel") { perform(.cancelSelection) }

                Spacer()

                Button(
                    allVisibleSelected ? "Deselect All" : "Select All"
                ) {
                    perform(.toggleSelectAll)
                }
                .disabled(selectionUnavailable)
            } else {
                if isAtRoot {
                    Button("Lock") { perform(.lock) }
                } else {
                    Button {
                        perform(.back)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                Spacer()

                Button("Select") {
                    perform(.beginSelection)
                }
                .disabled(selectionUnavailable)

                Button {
                    perform(.importContent)
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(importUnavailable)
                .accessibilityLabel(isAtRoot ? "Import to vault" : "Import to this folder")

                Menu {
                    Button {
                        perform(.newFolder)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        perform(.newVault)
                    } label: {
                        Label("Create New Vault", systemImage: "lock.badge.plus")
                    }

                    Button {
                        perform(.importVault)
                    } label: {
                        Label("Import Encrypted Vault", systemImage: "square.and.arrow.down.on.square")
                    }

                    Button {
                        perform(.exportVault)
                    } label: {
                        Label("Export Encrypted Vault", systemImage: "square.and.arrow.up.on.square")
                    }

                    Button {
                        perform(.verifyBackup)
                    } label: {
                        Label("Verify Backup", systemImage: "checkmark.shield")
                    }
                    .accessibilityIdentifier("vault-verify-backup")

                    Button {
                        perform(.vaultFiles)
                    } label: {
                        Label("Vault Files", systemImage: "folder.fill")
                    }

                    Button {
                        perform(.securitySettings)
                    } label: {
                        Label("Vault Security", systemImage: "shield.lefthalf.filled")
                    }

                    Button {
                        perform(.lock)
                    } label: {
                        Label("Lock KeyHollow", systemImage: "lock.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isWorking)
                .accessibilityLabel("Vault options")
            }
        }
        .overlay {
            Text(isSelecting ? "\(selectionCount) Selected" : title)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 120)
                .allowsHitTesting(false)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}
