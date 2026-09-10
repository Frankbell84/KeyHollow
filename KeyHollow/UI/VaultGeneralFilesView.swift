import SwiftUI
import KeyHollowGeneralFileSupportAddOn

struct VaultGeneralFilesView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    @State private var store: VaultGeneralFileStore?
    @State private var records: [VaultGeneralFileRecord] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var export: PreparedGeneralFileExport?
    @State private var exportTaskID: UUID?
    @State private var message: String?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty && !isWorking {
                    ContentUnavailableView(
                        "No Vault Files",
                        systemImage: "doc.badge.plus",
                        description: Text(
                            "Import documents, PDFs, audio, and other files as encrypted local copies."
                        )
                    )
                } else {
                    List(records, selection: $selectedIDs) { record in
                        fileRow(record)
                            .tag(record.id)
                            .contextMenu {
                                Button {
                                    selectedIDs = [record.id]
                                    exportSelected()
                                } label: {
                                    Label("Export to Files", systemImage: "square.and.arrow.up")
                                }

                                Button("Delete from Vault", role: .destructive) {
                                    selectedIDs = [record.id]
                                    showingDeleteConfirmation = true
                                }
                            }
                    }
                    .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting ? "Cancel" : "Done") {
                        if isSelecting {
                            leaveSelectionMode()
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isWorking)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isSelecting {
                        Button("Select") { isSelecting = true }
                            .disabled(records.isEmpty || isWorking)
                        Button {
                            session.beginSystemInteraction()
                            isImporting = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isWorking)
                        .accessibilityLabel("Import files")
                    }
                }
                if isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            exportSelected()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedIDs.isEmpty || isWorking)

                        Spacer()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedIDs.isEmpty || isWorking)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            session.endSystemInteraction()
            importSelectedFiles(result)
        }
        .sheet(item: $export) { prepared in
            GeneralFileShareSheet(urls: prepared.urls) {
                finishExport(prepared)
            }
        }
        .confirmationDialog(
            "Delete Selected Files?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle, role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes the selected encrypted copies from this vault. Original files outside KeyHollow are not affected."
            )
        }
        .alert("KeyHollow", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .task(id: session.activeVaultID) {
            guard let expectedVaultID = session.activeVaultID else {
                store = nil
                records = []
                return
            }
            await session.performSensitiveTask { capability in
                await initializeStore(
                    expectedVaultID: expectedVaultID,
                    capability: capability
                )
            }
        }
    }

    private var navigationTitle: String {
        return isSelecting ? "\(selectedIDs.count) Selected" : "Vault Files"
    }

    private func fileRow(_ record: VaultGeneralFileRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: GeneralFilePresentation.iconName(for: record.contentTypeIdentifier))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayName)
                    .lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: Int64(record.originalByteCount), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isSelecting {
                Button {
                    selectedIDs = [record.id]
                    exportSelected()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(isWorking)
                .accessibilityLabel("Export \(record.displayName)")
            }
        }
    }

    private func initializeStore(
        expectedVaultID: UUID,
        capability: VaultAccessCapability
    ) async {
        guard store == nil,
              capability.vaultID == expectedVaultID else { return }
        do {
            let access = SessionGeneralFileAccess(capability: capability)
            let created = try VaultGeneralFileStore(
                vaultID: expectedVaultID,
                access: access
            )
            let loadedRecords = try await created.loadManifest().files
            try Task.checkCancellation()
            guard let currentContext = session.activeVaultContext(),
                  currentContext.id == expectedVaultID,
                  currentContext.access === capability,
                  !capability.isRevoked else { return }
            store = created
            records = loadedRecords
        } catch is CancellationError {
            return
        } catch VaultAccessError.revoked {
            return
        } catch {
            guard session.activeVaultID == expectedVaultID else { return }
            message = "The encrypted file store could not be opened."
        }
    }

    private func importSelectedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }
        guard !urls.isEmpty else { return }
        guard urls.count <= VaultGeneralFileStore.maximumBatchCount else {
            message = "Choose no more than \(VaultGeneralFileStore.maximumBatchCount) files at a time."
            return
        }
        guard let store, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                let outcome = try await store.importFiles(at: urls)
                guard !Task.isCancelled else { return }
                records = try await store.loadManifest().files
                message = GeneralFileImportPresentation.message(for: outcome)
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be imported into this vault."
            }
        }
    }

    private var selectedRecords: [VaultGeneralFileRecord] {
        records.filter { selectedIDs.contains($0.id) }
    }

    private var deleteButtonTitle: String {
        let noun = selectedIDs.count == 1 ? "File" : "Files"
        return "Delete \(selectedIDs.count) \(noun) from Vault"
    }

    private func exportSelected() {
        let selection = selectedRecords
        guard let store, !selection.isEmpty, !isWorking else { return }
        isWorking = true
        let taskID = session.startSensitiveTask { _ in
            do {
                let prepared = try await store.prepareExport(selection)
                guard !Task.isCancelled else {
                    await store.discardExport(prepared)
                    isWorking = false
                    return
                }
                session.beginSystemInteraction()
                export = prepared
                await waitForExportDismissal()
                // `discardExport` deliberately ignores cancellation. Keeping
                // this registered task alive until deletion means session lock
                // and vault deletion cannot finish while plaintext remains.
                await store.discardExport(prepared)
                if export?.id == prepared.id {
                    export = nil
                    session.endSystemInteraction()
                }
            } catch is CancellationError {
                // The store owns cleanup for cancellation during preparation.
            } catch {
                message = "The selected files could not be authenticated and exported."
            }
            exportTaskID = nil
            isWorking = false
        }
        exportTaskID = taskID
        if taskID == nil { isWorking = false }
    }

    private func finishExport(_ prepared: PreparedGeneralFileExport) {
        export = nil
        session.endSystemInteraction()
        guard let taskID = exportTaskID else { return }
        session.cancelSensitiveTask(taskID)
    }

    private func waitForExportDismissal() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                return
            }
        }
    }

    private func deleteSelected() {
        let selection = selectedRecords
        guard let store, !selection.isEmpty, !isWorking else { return }
        isWorking = true
        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await store.delete(selection)
                records = try await store.loadManifest().files
                leaveSelectionMode()
                let noun = selection.count == 1 ? "file" : "files"
                message = "Deleted \(selection.count) \(noun) from this vault."
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be deleted from the vault."
            }
        }
    }

    private func leaveSelectionMode() {
        isSelecting = false
        selectedIDs.removeAll()
    }
}
