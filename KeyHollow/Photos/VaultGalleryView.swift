import SwiftUI
import UIKit
import UniformTypeIdentifiers
import KeyHollowEncryptedVideoAddOn
import KeyHollowFolderPresentationAddOn
import KeyHollowGalleryUI
import KeyHollowGeneralFileSupportAddOn
import KeyHollowPhotoCore
import KeyHollowPhotosAdapter
import KeyHollowSecurePreviewAddOn

private enum VaultImportMode {
    case copy
    case move
}

private struct VaultImportProgress {
    let mode: VaultImportMode
    let total: Int
    var importedCount = 0
    var failedCount = 0
    var identifiersToDelete: [String] = []
}

/// App-owned routing record. Storage models stop here and are translated into
/// immutable, source-neutral values before crossing into `KeyHollowGalleryUI`.
enum VaultGalleryContentItem: Identifiable, Equatable {
    case photo(VaultPhotoRecord)
    case generalFile(VaultGeneralFileRecord)

    var id: VaultGallerySelection.Item {
        switch self {
        case .photo(let record):
            .photo(record.id)
        case .generalFile(let record):
            .generalFile(record.id)
        }
    }

    var sourceID: UUID {
        switch self {
        case .photo(let record):
            record.id
        case .generalFile(let record):
            record.id
        }
    }

    var presentationItem: VaultGalleryPresentationItem {
        switch self {
        case .photo(let record):
            return VaultGalleryPresentationItem(
                id: id,
                importedAt: record.importedAt,
                displayName: record.displayName,
                originalByteCount: record.originalByteCount,
                isImage: true,
                fallbackTitle: "Photo",
                iconName: "photo",
                accessibilityKind: "Encrypted photo"
            )
        case .generalFile(let record):
            let image = Self.isImage(record)
            return VaultGalleryPresentationItem(
                id: id,
                importedAt: record.importedAt,
                displayName: record.displayName,
                originalByteCount: record.originalByteCount,
                isImage: image,
                fallbackTitle: "File",
                iconName: GeneralFilePresentation.iconName(
                    for: record.contentTypeIdentifier
                ),
                accessibilityKind: "Encrypted file"
            )
        }
    }

    static func sourceNeutralOrder(
        _ first: Self,
        _ second: Self
    ) -> Bool {
        VaultGalleryPresentationItem.sourceNeutralOrder(
            first.presentationItem,
            second.presentationItem
        )
    }

    var openRoute: VaultGalleryOpenRoute {
        switch self {
        case .photo:
            return .imagePreview
        case .generalFile(let record):
            let securePreviewKind = VaultSecurePreviewPolicy.kind(
                for: VaultSecurePreviewDescriptor(
                    displayName: record.displayName,
                    contentTypeIdentifier: record.contentTypeIdentifier,
                    originalByteCount: record.originalByteCount
                )
            )
            if securePreviewKind == .image {
                return .imagePreview
            }

            let encryptedVideoKind = VaultEncryptedVideoPolicy.kind(
                for: VaultEncryptedVideoDescriptor(
                    displayName: record.displayName,
                    contentTypeIdentifier: record.contentTypeIdentifier,
                    originalByteCount: record.originalByteCount
                )
            )
            return encryptedVideoKind == .video ? .videoPlayback : .fileManagement
        }
    }

    private static func isImage(_ record: VaultGeneralFileRecord) -> Bool {
        VaultSecurePreviewPolicy.kind(
            for: VaultSecurePreviewDescriptor(
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                originalByteCount: record.originalByteCount
            )
        ) == .image
    }
}

enum VaultGalleryOpenRoute: Equatable {
    case imagePreview
    case videoPlayback
    case fileManagement
}

/// One immutable bridge between protected source records and the compiled,
/// source-neutral gallery UI. Presentation values are built and sorted once;
/// a tile recovers its source record with a constant-time lookup instead of
/// rebuilding the complete mixed gallery during every cell evaluation.
struct VaultGalleryContentSnapshot {
    let orderedSources: [VaultGalleryContentItem]
    let presentations: [VaultGalleryPresentationItem]
    let sourceByID: [VaultGallerySelection.Item: VaultGalleryContentItem]

    init(items: [VaultGalleryContentItem]) {
        let entries = items.map { source in
            (source: source, presentation: source.presentationItem)
        }.sorted {
            VaultGalleryPresentationItem.sourceNeutralOrder(
                $0.presentation,
                $1.presentation
            )
        }

        orderedSources = entries.map(\.source)
        presentations = entries.map(\.presentation)
        sourceByID = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.presentation.id, $0.source) }
        )
    }

    var selectableItems: [VaultGallerySelection.Item] {
        presentations.map(\.id)
    }
}

private struct ActiveVaultImagePreview: Identifiable {
    let source: VaultGalleryContentItem
    let placeholder: UIImage?

    var id: UUID { source.sourceID }
}

/// Gives encrypted thumbnail cache hits a responsive lane while bounding the
/// complete Files-origin cache-miss path to one full plaintext payload at a
/// time. The permit intentionally covers authenticated original loading,
/// bounded ImageIO preparation, and encrypted cache persistence so cell tasks
/// cannot queue multiple large decrypted files between otherwise independent
/// actors. Queued duplicate misses recheck the encrypted cache after the first
/// request completes.
struct VaultGeneralFileThumbnailPipelineHooks: Sendable {
    var didAcquireColdPermit: @Sendable () async -> Void
    var didPrepareVideoPlaintext: @Sendable () async -> Void

    init(
        didAcquireColdPermit: @escaping @Sendable () async -> Void = {},
        didPrepareVideoPlaintext: @escaping @Sendable () async -> Void = {}
    ) {
        self.didAcquireColdPermit = didAcquireColdPermit
        self.didPrepareVideoPlaintext = didPrepareVideoPlaintext
    }
}

actor VaultGeneralFileThumbnailPipeline {
    private enum PipelineError: Error {
        case unsupportedItem
        case invalidPreparedExport
    }

    private struct PermitWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let cachedThumbnailDecoder = VaultSecureImageProcessor()
    private let cacheMissImageProcessor = VaultSecureImageProcessor()
    private let hooks: VaultGeneralFileThumbnailPipelineHooks
    private var isOccupied = false
    private var waiters: [PermitWaiter] = []

    init(hooks: VaultGeneralFileThumbnailPipelineHooks = .init()) {
        self.hooks = hooks
    }

    func image(
        for record: VaultGeneralFileRecord,
        generalFileStore: VaultGeneralFileStore,
        presentationStore: VaultFolderPresentationStore
    ) async throws -> VaultSecureRenderedImage {
        let reference = VaultPresentedContentReference(kind: .generalFile, id: record.id)
        return try await loadOrGenerate(
            loadCached: { [self] in
                try await loadCachedThumbnail(
                    for: reference,
                    presentationStore: presentationStore
                )
            },
            generate: { [self] in
                try await generateThumbnail(
                    for: record,
                    reference: reference,
                    generalFileStore: generalFileStore,
                    presentationStore: presentationStore
                )
            }
        )
    }

    /// Shared cache/cold-work primitive used by both Files-origin images and
    /// videos. Keeping this internal gives deterministic tests direct access
    /// to the production permit and duplicate-cache recheck semantics.
    func loadOrGenerate<Value: Sendable>(
        loadCached: @escaping @Sendable () async throws -> Value?,
        generate: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let cachedValue = try await loadCached() {
            return cachedValue
        }

        guard await acquire() else { throw CancellationError() }
        defer { release() }
        try Task.checkCancellation()

        if let cachedValue = try await loadCached() {
            return cachedValue
        }

        await hooks.didAcquireColdPermit()
        try Task.checkCancellation()
        return try await generate()
    }

    private func generateThumbnail(
        for record: VaultGeneralFileRecord,
        reference: VaultPresentedContentReference,
        generalFileStore: VaultGeneralFileStore,
        presentationStore: VaultFolderPresentationStore
    ) async throws -> VaultSecureRenderedImage {

        let securePreviewKind = VaultSecurePreviewPolicy.kind(
            for: VaultSecurePreviewDescriptor(
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                originalByteCount: record.originalByteCount
            )
        )
        if securePreviewKind == .image {
            try Task.checkCancellation()
            let originalData = try await generalFileStore.loadFile(record)
            try Task.checkCancellation()
            let thumbnail = try await cacheMissImageProcessor.prepareThumbnail(from: originalData)
            try Task.checkCancellation()
            try await presentationStore.storeThumbnail(thumbnail.encodedData, for: reference)
            try Task.checkCancellation()
            return thumbnail.renderedImage
        }

        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: record.displayName,
            contentTypeIdentifier: record.contentTypeIdentifier,
            originalByteCount: record.originalByteCount
        )
        guard VaultEncryptedVideoPolicy.kind(for: descriptor) == .video else {
            throw PipelineError.unsupportedItem
        }

        try Task.checkCancellation()
        let prepared = try await generalFileStore.prepareExport([record])
        do {
            await hooks.didPrepareVideoPlaintext()
            try Task.checkCancellation()
            guard prepared.urls.count == 1, let fileURL = prepared.urls.first else {
                throw PipelineError.invalidPreparedExport
            }
            let playback = try VaultPreparedVideoPlayback(
                id: record.id,
                descriptor: descriptor,
                fileURL: fileURL
            )
            let videoThumbnail = try await VaultEncryptedVideoThumbnailRenderer.render(playback)
            try Task.checkCancellation()

            // The original plaintext is gone before its bounded JPEG enters
            // the encrypted presentation cache.
            await generalFileStore.discardExport(prepared)
            try Task.checkCancellation()
            let renderedImage = try await cachedThumbnailDecoder.decodeThumbnail(
                from: videoThumbnail.jpegData
            )
            try Task.checkCancellation()
            try await presentationStore.storeThumbnail(
                videoThumbnail.jpegData,
                for: reference
            )
            try Task.checkCancellation()
            return renderedImage
        } catch {
            // Idempotent cleanup covers cancellation and every failure point.
            await generalFileStore.discardExport(prepared)
            throw error
        }
    }

    private func loadCachedThumbnail(
        for reference: VaultPresentedContentReference,
        presentationStore: VaultFolderPresentationStore
    ) async throws -> VaultSecureRenderedImage? {
        try Task.checkCancellation()
        guard let cachedData = try await presentationStore.loadThumbnail(for: reference) else {
            return nil
        }
        try Task.checkCancellation()

        do {
            let image = try await cachedThumbnailDecoder.decodeThumbnail(from: cachedData)
            try Task.checkCancellation()
            return image
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            // Invalid cache data is regenerated from the authenticated original.
            return nil
        }
    }

    private func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if !isOccupied {
            isOccupied = true
            return true
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(PermitWaiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            isOccupied = false
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    func permitStateForTesting() -> (isOccupied: Bool, waiterCount: Int) {
        (isOccupied, waiters.count)
    }
}

/// Application composition coordinator. Visible folder/gallery layout,
/// tiles, and selection state are compiled in `KeyHollowGalleryUI`.
/// This shell alone translates UI actions into authenticated store operations.
struct VaultGalleryView: View {
    @EnvironmentObject private var session: VaultSession

    let service: VaultUnlockService

    @State private var store: VaultPhotoStore?
    @State private var records: [VaultPhotoRecord] = []
    @State private var generalFileStore: VaultGeneralFileStore?
    @State private var generalFileRecords: [VaultGeneralFileRecord] = []
    @State private var presentationStore: VaultFolderPresentationStore?
    @State private var folderManifest = VaultFolderPresentationManifest.empty
    @State private var activeFolderID: UUID?
    @State private var contentStoresLoaded = false
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var generalFileThumbnails: [UUID: UIImage] = [:]
    @State private var activeImagePreview: ActiveVaultImagePreview?
    @State private var preparedImagePreview: VaultSecureImagePreview?
    @State private var previewTaskID: UUID?
    @State private var generalFileExport: PreparedGeneralFileExport?
    @State private var isSavingPreview = false
    @State private var previewMessage: String?
    @State private var showingImportOptions = false
    @State private var showingPicker = false
    @State private var showingFilePicker = false
    @State private var showingNewVault = false
    @State private var showingSecuritySettings = false
    @State private var showingEncryptedImport = false
    @State private var showingEncryptedExport = false
    @State private var showingVaultFiles = false
    @State private var showingDeleteSelectionConfirmation = false
    @State private var showingFolderEditor = false
    @State private var folderBeingRenamed: VaultFolderRecord?
    @State private var folderNameDraft = ""
    @State private var folderPendingDeletion: VaultFolderRecord?
    @State private var importMode: VaultImportMode = .copy
    @State private var isSelecting = false
    @State private var selection = VaultGallerySelection()
    @State private var isWorking = false
    @State private var message: String?
    @State private var importProgress: VaultImportProgress?
    @StateObject private var videoPlayback = VaultVideoPlaybackCoordinator()

    // SwiftUI recreates View values freely. State preserves these actor
    // identities so decoding and full-payload bounds survive recomposition.
    @State private var thumbnailImageProcessor = VaultSecureImageProcessor()
    @State private var previewImageProcessor = VaultSecureImageProcessor()
    @State private var generalFileThumbnailPipeline = VaultGeneralFileThumbnailPipeline()

    private let maximumCachedThumbnails = 48

    var body: some View {
        let snapshot = makeVisibleGallerySnapshot()

        VStack(spacing: 0) {
            galleryHeader(visibleItemIDs: snapshot.selectableItems)
            Divider()

            VaultGalleryGridView(
                isContentLoaded: contentStoresLoaded,
                isWorking: isWorking,
                emptyTitle: activeFolderID == nil ? "Empty Vault" : "Empty Folder",
                emptyDescription: emptyGalleryDescription,
                emptySystemImage: activeFolderID == nil
                    ? "photo.on.rectangle.angled"
                    : "folder",
                folders: visibleGalleryFolders,
                items: snapshot.presentations
            ) { folder in
                VaultFolderTileView(
                    folder: folder,
                    isEnabled: !isSelecting,
                    open: { openFolder(id: folder.id) },
                    rename: { requestFolderRename(id: folder.id) },
                    delete: { requestFolderDeletion(id: folder.id) }
                )
            } itemContent: { item in
                galleryItemCell(item, sourceByID: snapshot.sourceByID)
            }

            if isSelecting {
                Divider()
                selectionActionBar
            }
        }
        .confirmationDialog("Import to Vault", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Copy Photos to Vault") {
                importMode = .copy
                showingPicker = true
            }
            Button("Move Photos to Vault") {
                importMode = .move
                showingPicker = true
            }
            Button("Import Files to Vault") {
                session.beginSystemInteraction()
                showingFilePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Import encrypted copies from Photos or Files. Moving photos verifies the vault copies first, then asks iOS to delete the originals.")
        }
        .sheet(isPresented: $showingPicker) {
            SecurePhotoPicker(selectionLimit: 50) { event in
                await handleImportEvent(event)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            session.endSystemInteraction()
            importGeneralFiles(result)
        }
        .sheet(isPresented: $showingNewVault) {
            AdditionalVaultSetupView(service: service)
                .environmentObject(session)
        }
        .sheet(isPresented: $showingSecuritySettings) {
            VaultSecuritySettingsView(service: service)
                .environmentObject(session)
        }
        .sheet(isPresented: $showingEncryptedImport) {
            EncryptedVaultImportView(service: service)
                .environmentObject(session)
        }
        .sheet(isPresented: $showingEncryptedExport) {
            EncryptedVaultExportView(service: service)
                .environmentObject(session)
        }
        .sheet(isPresented: $showingVaultFiles, onDismiss: {
            Task { await reloadGeneralFiles() }
        }) {
            VaultGeneralFilesView()
                .environmentObject(session)
        }
        .sheet(item: $generalFileExport) { prepared in
            GeneralFileShareSheet(urls: prepared.urls) {
                finishGeneralFileExport(prepared)
            }
        }
        .sheet(item: $activeImagePreview, onDismiss: clearActiveImagePreview) { active in
            VaultSecureImagePreviewView(
                preview: $preparedImagePreview,
                placeholder: active.placeholder,
                displayName: active.source.presentationItem.title,
                isLoading: isWorking && preparedImagePreview == nil,
                isSaving: isSavingPreview,
                message: $previewMessage,
                onDismiss: clearActiveImagePreview,
                onSave: {
                    if let preparedImagePreview {
                        savePreviewToPhotos(preparedImagePreview)
                    }
                },
                onDelete: { deletePreviewSource(active.source) }
            )
        }
        .sheet(
            item: Binding(
                get: { videoPlayback.active },
                set: { active in
                    if active == nil {
                        videoPlayback.dismiss()
                    }
                }
            ),
            onDismiss: { videoPlayback.dismiss() }
        ) { active in
            VaultEncryptedVideoPlayerView(
                playback: active.playback,
                onPlayerWillAttach: {
                    videoPlayback.playerWillAttach(active.playback.id)
                },
                onPlayerReleased: {
                    videoPlayback.playerDidRelease(active.playback.id)
                },
                onDismiss: { videoPlayback.dismiss() },
                onFailure: { _ in
                    videoPlayback.dismiss()
                    message = "The video stopped because iOS could not continue secure playback."
                }
            )
        }
        .confirmationDialog(
            "Delete Selected Items?",
            isPresented: $showingDeleteSelectionConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteSelectionButtonTitle, role: .destructive) {
                deleteSelectedItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the selected encrypted copies from this vault. Originals outside KeyHollow are not affected.")
        }
        .alert(folderEditorTitle, isPresented: $showingFolderEditor) {
            TextField("Folder name", text: $folderNameDraft)
            Button(folderEditorActionTitle) {
                saveFolderName()
            }
            .disabled(normalizedFolderNameDraft.isEmpty)
            Button("Cancel", role: .cancel) {
                folderBeingRenamed = nil
                folderNameDraft = ""
            }
        } message: {
            Text("Folders organize encrypted items without changing or duplicating their protected contents.")
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderPendingDeletion {
                    deleteFolder(folder)
                }
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                folderPendingDeletion = nil
            }
        } message: {
            Text("The folder will be removed. Its photos and files will return to the vault root and will not be deleted.")
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
            await videoPlayback.dismissAndWait()
            store = nil
            records = []
            generalFileStore = nil
            generalFileRecords = []
            presentationStore = nil
            folderManifest = .empty
            activeFolderID = nil
            contentStoresLoaded = false
            thumbnails = [:]
            generalFileThumbnails = [:]
            clearActiveImagePreview()
            leaveSelectionMode()
            await initializeStores()
            contentStoresLoaded = true
        }
        .onChange(of: session.securityEpoch) { _, _ in
            videoPlayback.dismiss()
        }
        .onDisappear {
            videoPlayback.dismiss()
        }
    }

    private func galleryHeader(
        visibleItemIDs: [VaultGallerySelection.Item]
    ) -> some View {
        HStack(spacing: 18) {
            if isSelecting {
                Button("Cancel") { leaveSelectionMode() }

                Spacer()

                Button(
                    selection.containsAll(visibleItemIDs) ? "Deselect All" : "Select All"
                ) {
                    toggleSelectAll(visibleItemIDs)
                }
                .disabled(visibleItemIDs.isEmpty || isWorking)
            } else {
                if activeFolderID == nil {
                    Button("Lock") { lockVaultAndFinishCleanup() }
                } else {
                    Button {
                        leaveSelectionMode()
                        activeFolderID = nil
                    } label: {
                        Label("Vault", systemImage: "chevron.left")
                    }
                }

                Spacer()

                Button("Select") {
                    isSelecting = true
                }
                .disabled(visibleItemIDs.isEmpty || isWorking)

                if activeFolderID == nil {
                    Button {
                        showingImportOptions = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isWorking)
                    .accessibilityLabel("Import to vault")
                }

                Menu {
                    if activeFolderID == nil {
                        Button {
                            requestNewFolder()
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    }

                    Button {
                        showingNewVault = true
                    } label: {
                        Label("Create New Vault", systemImage: "lock.badge.plus")
                    }

                    Button {
                        showingEncryptedImport = true
                    } label: {
                        Label("Import Encrypted Vault", systemImage: "square.and.arrow.down.on.square")
                    }

                    Button {
                        showingEncryptedExport = true
                    } label: {
                        Label("Export Encrypted Vault", systemImage: "square.and.arrow.up.on.square")
                    }

                    Button {
                        showingVaultFiles = true
                    } label: {
                        Label("Vault Files", systemImage: "folder.fill")
                    }

                    Button {
                        showingSecuritySettings = true
                    } label: {
                        Label("Vault Security", systemImage: "shield.lefthalf.filled")
                    }

                    Button {
                        lockVaultAndFinishCleanup()
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
            Text(isSelecting ? "\(selection.count) Selected" : galleryTitle)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 120)
                .allowsHitTesting(false)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var selectionActionBar: some View {
        HStack {
            selectionTransferAction

            Spacer()

            selectionMoveAction

            Spacer()

            Button(role: .destructive) {
                showingDeleteSelectionConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty || isWorking)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var selectionTransferAction: some View {
        switch selection.transferMode {
        case .none:
            EmptyView()
        case .photos:
            Button {
                saveSelectedPhotos()
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            .disabled(isWorking)
        case .generalFiles:
            Button {
                exportSelectedGeneralFiles()
            } label: {
                Label("Export Files", systemImage: "square.and.arrow.up")
            }
            .disabled(isWorking)
        case .mixed:
            Menu {
                Button {
                    saveSelectedPhotos()
                } label: {
                    Label("Save Photos", systemImage: "square.and.arrow.down")
                }

                Button {
                    exportSelectedGeneralFiles()
                } label: {
                    Label("Export Files", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("Save / Export", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(isWorking)
        }
    }

    private func lockVaultAndFinishCleanup() {
        let barrier = session.lock()
        Task {
            await barrier.wait()
        }
    }

    private var selectionMoveAction: some View {
        Menu {
            if activeFolderID != nil {
                Button {
                    moveSelectedItems(to: nil)
                } label: {
                    Label("Vault Root", systemImage: "rectangle.grid.3x2")
                }
            }

            ForEach(sortedFolders) { folder in
                if folder.id != activeFolderID {
                    Button {
                        moveSelectedItems(to: folder.id)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                }
            }
        } label: {
            Label("Move", systemImage: "folder")
        }
        .disabled(selection.isEmpty || !hasSelectionMoveDestination || isWorking)
    }

    private var sortedFolders: [VaultFolderRecord] {
        folderManifest.folders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var visibleFolders: [VaultFolderRecord] {
        activeFolderID == nil ? sortedFolders : []
    }

    private var visibleGalleryFolders: [VaultGalleryFolder] {
        visibleFolders.map {
            VaultGalleryFolder(
                id: $0.id,
                name: $0.name,
                itemCount: itemCount(in: $0.id)
            )
        }
    }

    private func makeVisibleGallerySnapshot() -> VaultGalleryContentSnapshot {
        var folderIDByItem: [VaultPresentedContentReference: UUID] = [:]
        folderIDByItem.reserveCapacity(folderManifest.memberships.count)
        for membership in folderManifest.memberships {
            folderIDByItem[membership.item] = membership.folderID
        }

        var items: [VaultGalleryContentItem] = []
        items.reserveCapacity(records.count + generalFileRecords.count)
        for record in records where folderIDByItem[
            VaultPresentedContentReference(kind: .photo, id: record.id)
        ] == activeFolderID {
            items.append(.photo(record))
        }
        for record in generalFileRecords where folderIDByItem[
            VaultPresentedContentReference(kind: .generalFile, id: record.id)
        ] == activeFolderID {
            items.append(.generalFile(record))
        }

        return VaultGalleryContentSnapshot(items: items)
    }

    private var visiblePhotoRecords: [VaultPhotoRecord] {
        makeVisibleGallerySnapshot().orderedSources.compactMap {
            guard case .photo(let record) = $0 else { return nil }
            return record
        }
    }

    private var visibleGeneralFileRecords: [VaultGeneralFileRecord] {
        makeVisibleGallerySnapshot().orderedSources.compactMap {
            guard case .generalFile(let record) = $0 else { return nil }
            return record
        }
    }

    private var activeFolder: VaultFolderRecord? {
        guard let activeFolderID else { return nil }
        return folderManifest.folders.first { $0.id == activeFolderID }
    }

    private var galleryTitle: String {
        activeFolder?.name ?? "Vault"
    }

    private var emptyGalleryDescription: String {
        if activeFolderID == nil {
            return "Import photos or files to store encrypted copies inside this vault."
        }
        return "Move photos or files here from a selection or an item's menu."
    }

    private var hasSelectionMoveDestination: Bool {
        activeFolderID != nil || sortedFolders.contains { $0.id != activeFolderID }
    }

    private var folderEditorTitle: String {
        folderBeingRenamed == nil ? "New Folder" : "Rename Folder"
    }

    private var folderEditorActionTitle: String {
        folderBeingRenamed == nil ? "Create" : "Save"
    }

    private var normalizedFolderNameDraft: String {
        folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func assignedFolderID(
        for item: VaultPresentedContentReference
    ) -> UUID? {
        folderManifest.memberships.first { $0.item == item }?.folderID
    }

    private func itemCount(in folderID: UUID) -> Int {
        folderManifest.memberships.filter { $0.folderID == folderID }.count
    }

    @ViewBuilder
    private func moveDestinationMenu(
        for item: VaultPresentedContentReference
    ) -> some View {
        let currentFolderID = assignedFolderID(for: item)
        let hasDestination = currentFolderID != nil
            || sortedFolders.contains { $0.id != currentFolderID }

        if hasDestination {
            Menu {
                if currentFolderID != nil {
                    Button {
                        move(item, to: nil)
                    } label: {
                        Label("Vault Root", systemImage: "rectangle.grid.3x2")
                    }
                }

                ForEach(sortedFolders) { folder in
                    if folder.id != currentFolderID {
                        Button {
                            move(item, to: folder.id)
                        } label: {
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                }
            } label: {
                Label("Move", systemImage: "folder")
            }
        }
    }

    @ViewBuilder
    private func galleryItemCell(
        _ presentationItem: VaultGalleryPresentationItem,
        sourceByID: [VaultGallerySelection.Item: VaultGalleryContentItem]
    ) -> some View {
        if let item = sourceByID[presentationItem.id] {
            VaultGalleryItemTileView(
                item: presentationItem,
                thumbnail: thumbnail(for: item),
                selectionState: isSelecting ? selection.contains(item.id) : nil,
                action: { handleGalleryItemTap(item) }
            )
            .contextMenu {
                galleryItemContextMenu(item)
            }
            .task(id: item.id, priority: .utility) {
                await loadThumbnailIfNeeded(for: item)
            }
        }
    }

    @ViewBuilder
    private func galleryItemContextMenu(
        _ item: VaultGalleryContentItem
    ) -> some View {
        switch item {
        case .photo(let record):
            Button {
                savePhotos([record])
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }

            Button {
                isSelecting = true
                selection.selectOnly(item.id)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }

            moveDestinationMenu(for: presentedReference(for: item))

            Button("Delete from Vault", role: .destructive) {
                delete(record)
            }

        case .generalFile(let record):
            Button {
                exportGeneralFiles([record])
            } label: {
                Label("Export to Files", systemImage: "square.and.arrow.up")
            }

            Button {
                isSelecting = true
                selection.selectOnly(item.id)
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }

            moveDestinationMenu(for: presentedReference(for: item))

            Button {
                showingVaultFiles = true
            } label: {
                Label("Manage File", systemImage: "doc")
            }
        }
    }

    private func handleGalleryItemTap(_ item: VaultGalleryContentItem) {
        if isSelecting {
            selection.toggle(item.id)
            return
        }

        switch item.openRoute {
        case .imagePreview:
            openImage(item)
        case .videoPlayback:
            guard case .generalFile(let record) = item else { return }
            openVideo(record)
        case .fileManagement:
            showingVaultFiles = true
        }
    }

    private func thumbnail(for item: VaultGalleryContentItem) -> UIImage? {
        switch item {
        case .photo(let record):
            thumbnails[record.id]
        case .generalFile(let record):
            generalFileThumbnails[record.id]
        }
    }

    @MainActor
    private func loadThumbnailIfNeeded(
        for item: VaultGalleryContentItem
    ) async {
        switch item {
        case .photo(let record):
            await loadThumbnailIfNeeded(record)
        case .generalFile(let record):
            await loadGeneralFileThumbnailIfNeeded(record)
        }
    }

    private func presentedReference(
        for item: VaultGalleryContentItem
    ) -> VaultPresentedContentReference {
        switch item {
        case .photo(let record):
            VaultPresentedContentReference(kind: .photo, id: record.id)
        case .generalFile(let record):
            VaultPresentedContentReference(kind: .generalFile, id: record.id)
        }
    }

    private func initializeStores() async {
        guard let context = session.activeVaultContext() else { return }

        if store == nil {
            do {
                let createdStore = try VaultPhotoStore(vaultID: context.id, access: context.access)
                store = createdStore
                try await reload(using: createdStore)
            } catch {
                store = nil
                message = "The encrypted photo store could not be opened."
            }
        }

        if presentationStore == nil {
            do {
                let access = SessionFolderPresentationAccess(capability: context.access)
                let createdStore = try VaultFolderPresentationStore(
                    vaultID: context.id,
                    access: access
                )
                presentationStore = createdStore
                folderManifest = try await createdStore.loadManifest()
            } catch {
                presentationStore = nil
                message = "The encrypted presentation store could not be opened."
            }
        }

        if generalFileStore == nil {
            do {
                let access = SessionGeneralFileAccess(capability: context.access)
                let createdStore = try VaultGeneralFileStore(vaultID: context.id, access: access)
                generalFileStore = createdStore
                generalFileRecords = try await createdStore.loadManifest().files
            } catch {
                generalFileStore = nil
                message = "The encrypted file store could not be opened."
            }
        }

        await reconcilePresentationStore()
    }

    @MainActor
    private func reloadGeneralFiles() async {
        guard let generalFileStore else { return }
        do {
            generalFileRecords = try await generalFileStore.loadManifest().files
            let validIDs = Set(generalFileRecords.map(\.id))
            generalFileThumbnails = generalFileThumbnails.filter { validIDs.contains($0.key) }
            reconcileSelection()
            if isSelecting && visibleSelectableItems.isEmpty {
                leaveSelectionMode()
            }
            await reconcilePresentationStore()
        } catch {
            message = "The encrypted file list could not be refreshed."
        }
    }

    @MainActor
    private func reconcilePresentationStore() async {
        guard let presentationStore,
              store != nil,
              generalFileStore != nil,
              session.isUnlocked else { return }

        let photoItems = records.map {
            VaultPresentedContentReference(kind: .photo, id: $0.id)
        }
        let fileItems = generalFileRecords.map {
            VaultPresentedContentReference(kind: .generalFile, id: $0.id)
        }

        do {
            try await presentationStore.reconcile(validItems: Set(photoItems + fileItems))
            folderManifest = try await presentationStore.loadManifest()
            if let activeFolderID,
               !folderManifest.folders.contains(where: { $0.id == activeFolderID }) {
                self.activeFolderID = nil
                leaveSelectionMode()
            }
        } catch is CancellationError {
            return
        } catch {
            message = "Folder organization could not be refreshed. Protected vault contents were not changed."
        }
    }

    private func requestNewFolder() {
        folderBeingRenamed = nil
        folderNameDraft = ""
        showingFolderEditor = true
    }

    private func requestFolderRename(id: UUID) {
        guard let folder = folderManifest.folders.first(where: { $0.id == id }) else {
            return
        }
        folderBeingRenamed = folder
        folderNameDraft = folder.name
        showingFolderEditor = true
    }

    private func requestFolderDeletion(id: UUID) {
        folderPendingDeletion = folderManifest.folders.first { $0.id == id }
    }

    private func saveFolderName() {
        let name = normalizedFolderNameDraft
        guard !name.isEmpty,
              let presentationStore,
              !isWorking else { return }

        let folderToRename = folderBeingRenamed
        showingFolderEditor = false
        folderBeingRenamed = nil
        folderNameDraft = ""
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                if let folderToRename {
                    try await presentationStore.renameFolder(id: folderToRename.id, to: name)
                } else {
                    _ = try await presentationStore.createFolder(named: name)
                }
                folderManifest = try await presentationStore.loadManifest()
            } catch VaultFolderPresentationStore.StoreError.duplicateFolderName {
                message = "A folder with that name already exists."
            } catch VaultFolderPresentationStore.StoreError.invalidFolderName {
                message = "Use a folder name between 1 and 80 characters."
            } catch is CancellationError {
                return
            } catch {
                message = "The encrypted folder could not be saved."
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func openFolder(id: UUID) {
        guard folderManifest.folders.contains(where: { $0.id == id }) else { return }
        guard !isWorking else { return }
        leaveSelectionMode()
        activeFolderID = id
    }

    private func move(
        _ item: VaultPresentedContentReference,
        to folderID: UUID?
    ) {
        guard let presentationStore, !isWorking else { return }
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await presentationStore.move(item, to: folderID)
                folderManifest = try await presentationStore.loadManifest()
                selection.remove(selectionItem(for: item))
                if isSelecting && visibleSelectableItems.isEmpty {
                    leaveSelectionMode()
                }
            } catch is CancellationError {
                return
            } catch {
                message = "The item could not be moved. Protected vault contents were not changed."
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func moveSelectedItems(to folderID: UUID?) {
        let items = selectedPresentedReferences
        guard let presentationStore, !items.isEmpty, !isWorking else { return }
        let destinationName = folderID.flatMap { destinationID in
            folderManifest.folders.first { $0.id == destinationID }?.name
        } ?? "Vault Root"
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await presentationStore.move(items, to: folderID)
                folderManifest = try await presentationStore.loadManifest()
                guard !Task.isCancelled else { return }
                let movedCount = items.count
                leaveSelectionMode()
                let noun = movedCount == 1 ? "item" : "items"
                message = "Moved \(movedCount) \(noun) to \(destinationName)."
            } catch is CancellationError {
                return
            } catch {
                message = "The selected items could not be moved. Protected vault contents were not changed."
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func deleteFolder(_ folder: VaultFolderRecord) {
        guard let presentationStore, !isWorking else { return }
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await presentationStore.deleteFolder(id: folder.id)
                folderManifest = try await presentationStore.loadManifest()
                if activeFolderID == folder.id {
                    activeFolderID = nil
                    leaveSelectionMode()
                }
            } catch is CancellationError {
                return
            } catch {
                message = "The folder could not be deleted. Protected vault contents were not changed."
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func importGeneralFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        guard urls.count <= VaultGeneralFileStore.maximumBatchCount else {
            message = "Choose no more than \(VaultGeneralFileStore.maximumBatchCount) files at a time."
            return
        }
        guard let generalFileStore, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                let outcome = try await generalFileStore.importFiles(at: urls)
                guard !Task.isCancelled else { return }
                generalFileRecords = try await generalFileStore.loadManifest().files
                message = GeneralFileImportPresentation.message(for: outcome)
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be imported into this vault."
            }
        }
    }

    private func reload(using store: VaultPhotoStore) async throws {
        let manifest = try await store.loadManifest()

        records = manifest.photos
        let validIDs = Set(manifest.photos.map(\.id))
        thumbnails = thumbnails.filter { validIDs.contains($0.key) }
        reconcileSelection()

        if visibleSelectableItems.isEmpty {
            leaveSelectionMode()
        }
        await reconcilePresentationStore()
    }

    @MainActor
    private func handleImportEvent(_ event: PickedVaultPhotoEvent) async {
        switch event {
        case .started(let total):
            guard !isWorking else { return }
            isWorking = true
            importProgress = VaultImportProgress(mode: importMode, total: total)

        case .photo(let photo):
            guard var progress = importProgress,
                  let store,
                  session.isUnlocked,
                  !Task.isCancelled else { return }
            do {
                _ = try await store.importPhoto(
                    originalData: photo.originalData,
                    thumbnailData: photo.thumbnailData,
                    displayName: photo.displayName
                )
                progress.importedCount += 1
                if progress.mode == .move, let identifier = photo.sourceAssetIdentifier {
                    progress.identifiersToDelete.append(identifier)
                }
            } catch {
                progress.failedCount += 1
            }
            importProgress = progress

        case .failed:
            importProgress?.failedCount += 1

        case .finished:
            showingPicker = false
            guard let progress = importProgress else {
                isWorking = false
                return
            }
            importProgress = nil
            await finishImport(progress)
        }
    }

    @MainActor
    private func finishImport(_ progress: VaultImportProgress) async {
        guard let store, session.isUnlocked, !Task.isCancelled else {
            isWorking = false
            return
        }

        do {
            try await reload(using: store)
        } catch {
            message = "Photos were encrypted, but the gallery could not be refreshed."
        }

        if progress.mode == .move, progress.importedCount > 0 {
            let allImportedPhotosAreDeletable =
                progress.identifiersToDelete.count == progress.importedCount
            let result: PhotoMoveResult
            if allImportedPhotosAreDeletable {
                session.beginSystemPhotoOperation()
                result = await PhotoLibraryDeletionService.deleteOriginals(
                    localIdentifiers: progress.identifiersToDelete
                )
                session.endSystemPhotoOperation()
            } else {
                result = .copiedOnly
            }

            switch result {
            case .deleted:
                message = importResultMessage(
                    action: "Moved",
                    importedCount: progress.importedCount,
                    failedCount: progress.failedCount
                )
            case .copiedOnly:
                let base = importResultMessage(
                    action: "Encrypted",
                    importedCount: progress.importedCount,
                    failedCount: progress.failedCount
                )
                message = "\(base) iOS did not delete every original, so KeyHollow treats this batch as copied."
            }
        } else if progress.importedCount > 0 {
            message = importResultMessage(
                action: "Copied",
                importedCount: progress.importedCount,
                failedCount: progress.failedCount
            )
        } else if progress.failedCount > 0 {
            message = unreadableSelectionMessage(count: progress.failedCount)
        }
        isWorking = false
    }

    @MainActor
    private func loadThumbnailIfNeeded(_ record: VaultPhotoRecord) async {
        guard thumbnails[record.id] == nil,
              let store,
              session.isUnlocked else { return }
        guard let data = try? await store.loadThumbnail(record),
              !Task.isCancelled,
              let rendered = try? await thumbnailImageProcessor.decodeThumbnail(from: data),
              !Task.isCancelled else { return }

        if thumbnails.count >= maximumCachedThumbnails,
           let eviction = thumbnails.keys.first(where: { $0 != record.id }) {
            thumbnails.removeValue(forKey: eviction)
        }
        thumbnails[record.id] = rendered.image
    }

    @MainActor
    private func loadGeneralFileThumbnailIfNeeded(
        _ record: VaultGeneralFileRecord
    ) async {
        let securePreviewKind = VaultSecurePreviewPolicy.kind(
            for: VaultSecurePreviewDescriptor(
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                originalByteCount: record.originalByteCount
            )
        )
        let encryptedVideoKind = VaultEncryptedVideoPolicy.kind(
            for: VaultEncryptedVideoDescriptor(
                displayName: record.displayName,
                contentTypeIdentifier: record.contentTypeIdentifier,
                originalByteCount: record.originalByteCount
            )
        )
        guard generalFileThumbnails[record.id] == nil,
              let generalFileStore,
              let presentationStore,
              let activeVaultID = session.activeVaultID,
              session.isUnlocked,
              securePreviewKind == .image || encryptedVideoKind == .video else {
            return
        }

        await session.performSensitiveTask { capability in
            guard capability.vaultID == activeVaultID else { return }
            do {
                let renderedImage = try await generalFileThumbnailPipeline.image(
                    for: record,
                    generalFileStore: generalFileStore,
                    presentationStore: presentationStore
                )
                guard !Task.isCancelled,
                      session.activeVaultID == activeVaultID else { return }
                cacheGeneralFileThumbnail(renderedImage.image, id: record.id)
            } catch is CancellationError {
                return
            } catch {
                // A presentation preview must never block access to protected content.
                return
            }
        }
    }

    @MainActor
    private func cacheGeneralFileThumbnail(_ image: UIImage, id: UUID) {
        if generalFileThumbnails.count >= maximumCachedThumbnails,
           let eviction = generalFileThumbnails.keys.first(where: { $0 != id }) {
            generalFileThumbnails.removeValue(forKey: eviction)
        }
        generalFileThumbnails[id] = image
    }

    private func importResultMessage(action: String, importedCount: Int, failedCount: Int) -> String {
        let noun = importedCount == 1 ? "photo" : "photos"
        if failedCount > 0 {
            let failedNoun = failedCount == 1 ? "photo" : "photos"
            return "\(action) \(importedCount) \(noun) into KeyHollow. \(failedCount) \(failedNoun) could not be imported."
        }
        return "\(action) \(importedCount) \(noun) into KeyHollow."
    }

    private func unreadableSelectionMessage(count: Int) -> String {
        let noun = count == 1 ? "photo" : "photos"
        return "No photos were imported. \(count) selected \(noun) could not be read."
    }

    private func openImage(_ item: VaultGalleryContentItem) {
        guard item.openRoute == .imagePreview, !isWorking else { return }
        preparedImagePreview = nil
        previewMessage = nil
        activeImagePreview = ActiveVaultImagePreview(
            source: item,
            placeholder: thumbnail(for: item)
        )
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer {
                previewTaskID = nil
                isWorking = false
            }
            do {
                let data: Data
                switch item {
                case .photo(let record):
                    guard let store else {
                        message = "The encrypted photo store is unavailable."
                        return
                    }
                    data = try await store.loadPhoto(record)
                case .generalFile(let record):
                    guard let generalFileStore else {
                        message = "The encrypted file store is unavailable."
                        return
                    }
                    data = try await generalFileStore.loadFile(record)
                }
                guard !Task.isCancelled else { return }
                let preview = try await previewImageProcessor.preparePreview(
                    id: item.sourceID,
                    displayName: item.presentationItem.title,
                    originalData: data
                )
                guard !Task.isCancelled,
                      activeImagePreview?.source.id == item.id else { return }
                preparedImagePreview = preview
            } catch is CancellationError {
                return
            } catch {
                guard activeImagePreview?.source.id == item.id else { return }
                previewMessage = "The image could not be authenticated, validated, and opened."
            }
        }
        previewTaskID = taskID
        if taskID == nil {
            isWorking = false
            clearActiveImagePreview()
        }
    }

    private func delete(_ record: VaultPhotoRecord) {
        guard let store, !isWorking else { return }
        clearActiveImagePreview()
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await store.delete(record)
                try await reload(using: store)
            } catch is CancellationError {
                return
            } catch {
                message = "The photo could not be deleted from the vault."
            }
        }
    }

    private func delete(_ record: VaultGeneralFileRecord) {
        guard let generalFileStore, !isWorking else { return }
        clearActiveImagePreview()
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await generalFileStore.delete([record])
                generalFileRecords = try await generalFileStore.loadManifest().files
                generalFileThumbnails.removeValue(forKey: record.id)
                await reconcilePresentationStore()
            } catch is CancellationError {
                return
            } catch {
                message = "The file could not be deleted from the vault."
            }
        }
    }

    private func savePreviewToPhotos(_ preview: VaultSecureImagePreview) {
        guard !isSavingPreview else { return }
        isSavingPreview = true

        let taskID = session.startSensitiveTask { _ in
            session.beginSystemPhotoOperation()
            defer {
                session.endSystemPhotoOperation()
                isSavingPreview = false
            }
            let result = await PhotoLibrarySaveService.savePhoto(preview.originalData)
            guard !Task.isCancelled else { return }
            switch result {
            case .saved:
                previewMessage = "Saved to Photos. The encrypted vault copy was kept."
            case .permissionDenied:
                previewMessage = "Allow KeyHollow to add photos in iPhone Settings, then try again."
            case .failed:
                previewMessage = "This image could not be saved to Photos."
            }
        }
        if taskID == nil { isSavingPreview = false }
    }

    private func deletePreviewSource(_ source: VaultGalleryContentItem) {
        clearActiveImagePreview()
        switch source {
        case .photo(let record):
            delete(record)
        case .generalFile(let record):
            delete(record)
        }
    }

    private func clearActiveImagePreview() {
        if let previewTaskID {
            session.cancelSensitiveTask(previewTaskID)
            self.previewTaskID = nil
        }
        activeImagePreview = nil
        preparedImagePreview = nil
        previewMessage = nil
        if !session.isUnlocked { isSavingPreview = false }
    }

    private var selectedPhotoRecords: [VaultPhotoRecord] {
        visiblePhotoRecords.filter { selection.contains(.photo($0.id)) }
    }

    private var selectedGeneralFileRecords: [VaultGeneralFileRecord] {
        visibleGeneralFileRecords.filter { selection.contains(.generalFile($0.id)) }
    }

    private func openVideo(_ record: VaultGeneralFileRecord) {
        guard !isWorking, let generalFileStore else { return }
        message = nil
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await videoPlayback.prepare(record, using: generalFileStore)
            } catch is CancellationError {
                return
            } catch {
                guard session.isUnlocked else { return }
                message = "The video could not be authenticated, validated, and opened."
            }
        }
        if taskID == nil {
            isWorking = false
        }
    }

    private var selectedPresentedReferences: Set<VaultPresentedContentReference> {
        let photoReferences = selectedPhotoRecords.map {
            VaultPresentedContentReference(kind: .photo, id: $0.id)
        }
        let fileReferences = selectedGeneralFileRecords.map {
            VaultPresentedContentReference(kind: .generalFile, id: $0.id)
        }
        return Set(photoReferences + fileReferences)
    }

    private var visibleSelectableItems: [VaultGallerySelection.Item] {
        makeVisibleGallerySnapshot().selectableItems
    }

    private var allValidSelectableItems: [VaultGallerySelection.Item] {
        generalFileRecords.map { .generalFile($0.id) }
            + records.map { .photo($0.id) }
    }

    private var deleteSelectionButtonTitle: String {
        let noun = selection.count == 1 ? "Item" : "Items"
        return "Delete \(selection.count) \(noun) from Vault"
    }

    private func toggleSelectAll(_ visibleItemIDs: [VaultGallerySelection.Item]) {
        selection.toggleAll(visibleItemIDs)
    }

    private func leaveSelectionMode() {
        isSelecting = false
        selection.clear()
    }

    private func saveSelectedPhotos() {
        savePhotos(selectedPhotoRecords)
    }

    private func exportSelectedGeneralFiles() {
        exportGeneralFiles(selectedGeneralFileRecords)
    }

    private func exportGeneralFiles(_ files: [VaultGeneralFileRecord]) {
        guard let generalFileStore, !files.isEmpty, !isWorking else { return }
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                let prepared = try await generalFileStore.prepareExport(files)
                guard !Task.isCancelled else {
                    await generalFileStore.discardExport(prepared)
                    return
                }
                session.beginSystemInteraction()
                generalFileExport = prepared
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be authenticated and exported."
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func finishGeneralFileExport(_ prepared: PreparedGeneralFileExport) {
        generalFileExport = nil
        session.endSystemInteraction()
        guard let generalFileStore else { return }
        Task { await generalFileStore.discardExport(prepared) }
    }

    private func savePhotos(_ photos: [VaultPhotoRecord]) {
        guard let store, !photos.isEmpty, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            var savedCount = 0
            var failedCount = 0
            var permissionDenied = false

            session.beginSystemPhotoOperation()
            defer {
                session.endSystemPhotoOperation()
                isWorking = false
            }

            for photo in photos {
                guard !Task.isCancelled else { return }
                do {
                    // One decrypted original is resident at a time and is
                    // released before the next record is loaded.
                    let decryptedPhoto = try await store.loadPhoto(photo)
                    let result = await PhotoLibrarySaveService.savePhoto(decryptedPhoto)
                    switch result {
                    case .saved:
                        savedCount += 1
                    case .permissionDenied:
                        permissionDenied = true
                    case .failed:
                        failedCount += 1
                    }
                } catch {
                    failedCount += 1
                }
                if permissionDenied { break }
            }

            guard !Task.isCancelled else { return }
            if permissionDenied {
                message = "Allow KeyHollow to add photos in iPhone Settings, then try again."
            } else if savedCount > 0 {
                let noun = savedCount == 1 ? "photo" : "photos"
                if failedCount > 0 {
                    message = "Saved \(savedCount) \(noun) to Photos. \(failedCount) selected photos could not be decrypted or saved."
                } else {
                    message = "Saved \(savedCount) \(noun) to Photos. The encrypted vault copies were kept."
                }
                leaveSelectionMode()
            } else {
                message = "The selected photos could not be authenticated, decrypted, or saved."
            }
        }
    }

    private func deleteSelectedItems() {
        let photos = selectedPhotoRecords
        let files = selectedGeneralFileRecords
        guard !photos.isEmpty || !files.isEmpty, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            var deletedCount = 0
            var failedCount = 0

            if !photos.isEmpty {
                if let store {
                    do {
                        try await store.delete(photos)
                        deletedCount += photos.count
                    } catch is CancellationError {
                        return
                    } catch {
                        failedCount += photos.count
                    }
                } else {
                    failedCount += photos.count
                }
            }

            if !files.isEmpty {
                if let generalFileStore {
                    do {
                        try await generalFileStore.delete(files)
                        deletedCount += files.count
                    } catch is CancellationError {
                        return
                    } catch {
                        failedCount += files.count
                    }
                } else {
                    failedCount += files.count
                }
            }

            if let store {
                try? await reload(using: store)
            }
            if let generalFileStore {
                generalFileRecords = (try? await generalFileStore.loadManifest().files) ?? generalFileRecords
            }
            await reconcilePresentationStore()
            guard !Task.isCancelled else { return }
            leaveSelectionMode()

            if deletedCount > 0, failedCount == 0 {
                let noun = deletedCount == 1 ? "item" : "items"
                message = "Deleted \(deletedCount) \(noun) from this vault."
            } else if deletedCount > 0 {
                message = "Deleted \(deletedCount) selected items. \(failedCount) items could not be removed."
            } else {
                message = "The selected items could not be deleted from the vault."
            }
        }
    }

    private func selectionItem(
        for reference: VaultPresentedContentReference
    ) -> VaultGallerySelection.Item {
        switch reference.kind {
        case .photo:
            .photo(reference.id)
        case .generalFile:
            .generalFile(reference.id)
        }
    }

    private func reconcileSelection() {
        selection.reconcile(validItems: allValidSelectableItems)
    }
}

