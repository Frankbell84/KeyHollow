import SwiftUI
import UIKit
import UniformTypeIdentifiers
import KeyHollowCatalogSearchAddOn
import KeyHollowEncryptedVideoAddOn
import KeyHollowFolderPresentationAddOn
import KeyHollowGalleryUI
import KeyHollowGeneralFileSupportAddOn
import KeyHollowItemRenameAddOn
import KeyHollowMediaNavigationAddOn
import KeyHollowNestedFolderAddOn
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
    var rootFallbackCount = 0
}

private enum VaultMediaNavigationPresentationError: Error {
    case storeUnavailable
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
    @State private var thumbnailCache = VaultGalleryThumbnailCache()
    @State private var mediaNavigationQueue: VaultMediaNavigationQueue?
    @State private var mediaNavigationSources: [VaultMediaNavigationID: VaultGalleryContentItem] = [:]
    @State private var mediaNavigationGeneration: UInt64 = 0
    @State private var mediaNavigationTask: Task<Void, Never>?
    @State private var mediaChromeHideTask: Task<Void, Never>?
    @State private var isMediaChromeVisible = true
    @State private var failedMediaID: VaultMediaNavigationID?
    @State private var isClosingMediaNavigation = false
    @State private var isDeletingMedia = false
    @State private var generalFileExport: PreparedGeneralFileExport?
    @State private var generalFileExportTaskID: UUID?
    @State private var isSavingPreview = false
    @State private var imageSaveTaskID: UUID?
    @State private var previewMessage: String?
    @State private var showingImportOptions = false
    @State private var importDestination: VaultImportDestination?
    @State private var showingPicker = false
    @State private var showingFilePicker = false
    @State private var showingNewVault = false
    @State private var showingSecuritySettings = false
    @State private var showingEncryptedImport = false
    @State private var showingEncryptedExport = false
    @State private var showingBackupVerification = false
    @State private var showingVaultFiles = false
    @State private var showingDeleteSelectionConfirmation = false
    @State private var folderActions = VaultGalleryFolderActions()
    @State private var importMode: VaultImportMode = .copy
    @State private var isSelecting = false
    @State private var selection = VaultGallerySelection()
    @State private var searchText = ""
    @State private var catalogSortOrder: VaultCatalogSortOrder = .vaultOrder
    @State private var isWorking = false
    @State private var message: String?
    @State private var importProgress: VaultImportProgress?
    @State private var generalFileImportProgress: GeneralFileImportProgressState?
    @State private var isMediaImageZoomed = false
    @StateObject private var imagePreview = VaultImagePreviewCoordinator()
    @StateObject private var itemRename = VaultItemRenameCoordinator()
    @StateObject private var videoPlayback = VaultVideoPlaybackCoordinator()
    @StateObject private var videoPlaybackSession =
        VaultEncryptedVideoPlaybackSession()

    // SwiftUI recreates View values freely. State preserves these actor
    // identities so decoding and full-payload bounds survive recomposition.
    @State private var thumbnailImageProcessor = VaultSecureImageProcessor()
    @State private var previewImageProcessor = VaultSecureImageProcessor()
    @State private var generalFileThumbnailPipeline = VaultGeneralFileThumbnailPipeline()

    var body: some View {
        galleryLifecycleView
    }

    private var galleryCoreView: some View {
        let snapshot = locationSnapshot.filteredVisibleGallerySnapshot

        return VStack(spacing: 0) {
            galleryHeader(visibleItemIDs: snapshot.selectableItems)
            Divider()

            if !isSelecting {
                catalogSearchBar
                Divider()
                if activeFolderID != nil {
                    VaultFolderBreadcrumbView(segments: locationSnapshot.folderBreadcrumbSegments) {
                        navigateToFolder($0)
                    }
                    Divider()
                }
            }

            VaultGalleryGridView(
                isContentLoaded: contentStoresLoaded,
                isWorking: isWorking,
                emptyTitle: locationSnapshot.galleryEmptyTitle,
                emptyDescription: locationSnapshot.galleryEmptyDescription,
                emptySystemImage: locationSnapshot.galleryEmptySystemImage,
                folders: locationSnapshot.filteredVisibleGalleryFolders,
                items: snapshot.presentations
            ) { folder in
                VaultFolderTileView(
                    folder: folder,
                    isEnabled: !isSelecting,
                    open: { openFolder(id: folder.id) },
                    rename: { requestFolderRename(id: folder.id) },
                    move: { requestFolderMove(id: folder.id) },
                    delete: { requestFolderDeletion(id: folder.id) }
                )
            } itemContent: { item in
                galleryItemCell(item, snapshot: snapshot)
            }

            if isSelecting {
                Divider()
                selectionActionBar
            }
        }
    }

    private var galleryPresentationView: some View {
        galleryCoreView
        .overlay {
            if let generalFileImportProgress {
                GeneralFileImportProgressView(progress: generalFileImportProgress)
            }
        }
        .confirmationDialog(activeFolderID == nil ? "Import to Vault" : "Import to This Folder", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Copy Photos & Videos to Vault") {
                importMode = .copy
                showingPicker = true
            }
            Button("Move Photos & Videos to Vault") {
                importMode = .move
                showingPicker = true
            }
            Button("Import Files to Vault") {
                session.beginSystemInteraction()
                showingFilePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Import encrypted copies into the current location from Photos or Files. Moving Photos items verifies the vault copies first, then asks iOS to delete the originals.")
        }
        .sheet(isPresented: $showingPicker) {
            let destination = importDestination
            SecurePhotoPicker(selectionLimit: 50) { event in
                await handleImportEvent(event, destination: destination)
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
        .sheet(isPresented: $showingBackupVerification) {
            BackupVerificationCenterView()
                .environmentObject(session)
        }
        .sheet(isPresented: $showingVaultFiles, onDismiss: {
            session.startSensitiveTask { _ in
                await reloadGeneralFiles()
            }
        }) {
            VaultGeneralFilesView()
                .environmentObject(session)
        }
        .sheet(item: $generalFileExport) { prepared in
            GeneralFileShareSheet(urls: prepared.urls) {
                finishGeneralFileExport(prepared)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { mediaNavigationQueue != nil },
                set: { isPresented in
                    if !isPresented {
                        beginMediaNavigationDismissal()
                    }
                }
            )
        ) {
            mediaNavigationViewer
                .interactiveDismissDisabled()
        }
    }

    private var galleryMoveDestinationView: some View {
        galleryPresentationView
            .sheet(item: Binding(
                get: { folderActions.moveRequest },
                set: { if $0 == nil { folderActions.dismissMove() } }
            )) { request in
                VaultMoveDestinationPicker(
                    catalog: request.catalog,
                    prompt: request.prompt,
                    cancel: { folderActions.dismissMove() },
                    move: { destinationID in
                        folderActions.dismissMove()
                        performMove(request.target, to: destinationID)
                    }
                )
            }
    }

    private var galleryRenameView: some View {
        galleryMoveDestinationView
            .sheet(isPresented: Binding(
                get: { itemRename.isPresented },
                set: { if !$0 && itemRename.isPresented { itemRename.cancel(in: session) } }
            )) {
                ItemRenameEditor(
                    name: $itemRename.draft,
                    retainedExtension: itemRename.retainedExtension,
                    error: itemRename.error,
                    isSaving: itemRename.isSaving,
                    save: { itemRename.save() },
                    cancel: { itemRename.cancel(in: session) }
                )
            }
    }

    private var galleryAlertView: some View {
        galleryRenameView
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
        .alert(folderActions.editorTitle, isPresented: Binding(
            get: { folderActions.isEditorPresented },
            set: { if !$0 { folderActions.dismissEditor() } }
        )) {
            TextField("Folder name", text: $folderActions.nameDraft)
            Button(folderActions.editorActionTitle) {
                saveFolderName()
            }
            .disabled(folderActions.normalizedName.isEmpty)
            Button("Cancel", role: .cancel) {
                folderActions.clearNameDraft()
            }
        } message: {
            Text("Folders organize encrypted items without changing or duplicating their protected contents.")
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderActions.pendingDeletion != nil },
                set: { if !$0 { folderActions.dismissDeletion() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderActions.pendingDeletion {
                    deleteFolder(folder)
                }
                folderActions.dismissDeletion()
            }
            Button("Cancel", role: .cancel) {
                folderActions.dismissDeletion()
            }
        } message: {
            Text("The folder will be removed. Its direct items and child folders will return to the same parent location and will not be deleted.")
        }
        .alert("KeyHollow", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var galleryLifecycleView: some View {
        galleryAlertView
        .task(id: session.activeVaultID) {
            await resetMediaNavigationAndWait()
            store = nil
            records = []
            generalFileStore = nil
            generalFileRecords = []
            presentationStore = nil
            folderManifest = .empty
            activeFolderID = nil
            importDestination = nil
            importProgress = nil
            showingPicker = false
            showingFilePicker = false
            showingImportOptions = false
            folderActions.reset()
            searchText = ""
            contentStoresLoaded = false
            thumbnailCache.removeAll()
            leaveSelectionMode()
            await session.performSensitiveTask { capability in
                guard session.activeVaultID == capability.vaultID else { return }
                await initializeStores(expectedVaultID: capability.vaultID)
            }
            contentStoresLoaded = session.hasActiveAccess
        }
        .onChange(of: session.securityEpoch) { _, _ in
            itemRename.cancel(in: session)
            searchText = ""
            folderActions.reset()
            cancelMediaNavigationForLifecycle()
        }
        .onChange(of: activeFolderID) { _, _ in
            searchText = ""
            leaveSelectionMode()
        }
        .onChange(of: searchText) { _, _ in
            guard isSelecting else { return }
            selection.reconcile(validItems: locationSnapshot.filteredVisibleGallerySnapshot.selectableItems)
        }
        .onDisappear {
            // A full-screen media cover temporarily removes the gallery from
            // the visible hierarchy. The cover owns the active playback/image
            // lifecycle only while the vault still owns active access. A lock
            // must never let that temporary cover suppress terminal cleanup.
            guard !session.hasActiveAccess || mediaNavigationQueue == nil else {
                return
            }
            cancelMediaNavigationForLifecycle()
        }
    }

    @ViewBuilder
    private var mediaNavigationViewer: some View {
        if let queue = mediaNavigationQueue {
            VaultMediaNavigationPager(
                queue: queue,
                isNavigationEnabled: !isSavingPreview
                    && !isDeletingMedia
                    && !isClosingMediaNavigation
                    && !isMediaImageZoomed
                    && isMediaNavigationContentReady(queue),
                onSelectionChange: selectMediaNavigationItem,
                onDismissalRequested: beginMediaNavigationDismissal,
                onChromeToggleRequested: {
                    // The module-owned video session owns the native AVKit
                    // controls. Only image pages use a content
                    // tap to reveal or hide KeyHollow's action overlay.
                    guard VaultMediaChromeInteractionPolicy.acceptsContentTap(
                        for: queue.currentItem.kind
                    ) else { return }
                    toggleMediaChrome()
                }
            ) { item in
                mediaNavigationActiveContent(item)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if queue.currentItem.kind == .video {
                    mediaNavigationToolbar(for: queue)
                }
            }
            .overlay(alignment: .top) {
                if isMediaChromeVisible && queue.currentItem.kind == .image {
                    mediaNavigationToolbar(for: queue)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isMediaChromeVisible)
            .alert("KeyHollow", isPresented: Binding(
                get: { previewMessage != nil },
                set: { if !$0 { previewMessage = nil } }
            )) {
                Button("OK") { previewMessage = nil }
            } message: {
                Text(previewMessage ?? "")
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    private func mediaNavigationToolbar(
        for queue: VaultMediaNavigationQueue
    ) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(queue.currentItem.accessibilityTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(queue.accessibilityPosition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 96)

            HStack(spacing: 18) {
                Button("Done", action: beginMediaNavigationDismissal)
                    .disabled(
                        isSavingPreview
                            || isDeletingMedia
                            || isClosingMediaNavigation
                    )

                Spacer()

                if isSavingPreview || isDeletingMedia || isClosingMediaNavigation {
                    ProgressView()
                        .tint(.white)
                } else if queue.currentItem.kind == .image {
                    Button {
                        saveCurrentMediaImage()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Save to Photos")
                    .disabled(imagePreview.active?.id != queue.selectedID)
                }

                Button(role: .destructive) {
                    deleteCurrentMedia()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete from Vault")
                .disabled(isSavingPreview || isDeletingMedia || isClosingMediaNavigation)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func mediaNavigationActiveContent(
        _ item: VaultMediaNavigationItem
    ) -> some View {
        if isClosingMediaNavigation {
            ProgressView("Closing…")
                .tint(.white)
                .foregroundStyle(.white)
        } else {
            switch item.kind {
            case .image:
                VaultMediaImagePage(
                    coordinator: imagePreview,
                    item: item,
                    placeholder: mediaNavigationSources[item.id].flatMap {
                        thumbnail(for: $0)
                    },
                    isFailed: failedMediaID == item.id,
                    loadGeneration: mediaNavigationGeneration,
                    isInteractionDisabled: isSavingPreview
                        || isDeletingMedia
                        || isClosingMediaNavigation,
                    onRetry: { retryMediaNavigationItem(item.id) },
                    onImageWillAttach: {
                        imagePreview.imageWillAttach(item.id)
                    },
                    onImageReleased: {
                        imagePreview.imageDidRelease(item.id)
                    },
                    onZoomStateChange: { isZoomed in
                        isMediaImageZoomed = isZoomed
                    }
                )

            case .video:
                if let active = videoPlayback.active,
                   VaultGalleryContentItem.generalFile(active.source).mediaNavigationID == item.id {
                    VaultEncryptedVideoPlayerView(
                        session: videoPlaybackSession,
                        playback: active.playback,
                        onPlayerWillAttach: {
                            videoPlayback.playerWillAttach(active.playback.id)
                        },
                        onPlayerReleased: {
                            videoPlayback.playerDidRelease(active.playback.id)
                        },
                        onFailure: { _ in
                            handleMediaPlaybackFailure(for: item.id)
                        },
                        onDismissal: {
                            guard mediaNavigationQueue?.selectedID == item.id,
                                  videoPlayback.active?.playback.id == active.playback.id else {
                                return
                            }
                            beginMediaNavigationDismissal()
                        }
                    )
                } else {
                    mediaNavigationLoadState(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func mediaNavigationLoadState(
        for item: VaultMediaNavigationItem
    ) -> some View {
        if failedMediaID == item.id {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                Text("Unable to Open")
                    .font(.headline)
                Button("Try Again") {
                    retryMediaNavigationItem(item.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isSavingPreview
                        || isDeletingMedia
                        || isClosingMediaNavigation
                )
            }
            .padding()
            .foregroundStyle(.white)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .accessibilityElement(children: .contain)
        } else {
            ProgressView("Opening…")
                .padding()
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
    }

    private func galleryHeader(
        visibleItemIDs: [VaultGallerySelection.Item]
    ) -> some View {
        VaultGalleryHeaderControls(
            isSelecting: isSelecting,
            isAtRoot: activeFolderID == nil,
            title: locationSnapshot.galleryTitle,
            selectionCount: selection.count,
            allVisibleSelected: selection.containsAll(visibleItemIDs),
            selectionUnavailable: visibleItemIDs.isEmpty || isWorking,
            importUnavailable: isWorking || !contentStoresLoaded || presentationStore == nil,
            isWorking: isWorking
        ) { action in
            switch action {
            case .cancelSelection:
                leaveSelectionMode()
            case .toggleSelectAll:
                toggleSelectAll(visibleItemIDs)
            case .lock:
                lockVaultAndFinishCleanup()
            case .back:
                leaveSelectionMode()
                activeFolderID = locationSnapshot.activeFolder?.parentID
            case .beginSelection:
                isSelecting = true
            case .importContent:
                guard let vaultID = session.activeVaultID else { return }
                importDestination = VaultImportDestination(
                    vaultID: vaultID,
                    securityEpoch: session.securityEpoch,
                    folderID: activeFolderID
                )
                showingImportOptions = true
            case .newFolder:
                requestNewFolder()
            case .newVault:
                showingNewVault = true
            case .importVault:
                showingEncryptedImport = true
            case .exportVault:
                showingEncryptedExport = true
            case .verifyBackup:
                showingBackupVerification = true
            case .vaultFiles:
                showingVaultFiles = true
            case .securitySettings:
                showingSecuritySettings = true
            }
        }
    }

    private var catalogSearchBar: some View {
        VaultGallerySearchControls(
            searchText: $searchText,
            catalogSortOrder: $catalogSortOrder,
            isQueryEmpty: locationSnapshot.activeCatalogSearchQuery.isEmpty
        )
    }

    private var selectionActionBar: some View {
        VaultGallerySelectionControls(
            transferMode: selection.transferMode,
            isSelectionEmpty: selection.isEmpty,
            hasMoveDestination: locationSnapshot.hasSelectionMoveDestination,
            isWorking: isWorking
        ) { action in
            switch action {
            case .savePhotos:
                saveSelectedPhotos()
            case .exportFiles:
                exportSelectedGeneralFiles()
            case .move:
                requestSelectionMove()
            case .delete:
                showingDeleteSelectionConfirmation = true
            }
        }
    }

    private func lockVaultAndFinishCleanup() {
        let barrier = session.lock()
        Task {
            await barrier.wait()
        }
    }

    private var locationSnapshot: VaultGalleryLocationSnapshot {
        VaultGalleryLocationSnapshot(
            records: records,
            generalFileRecords: generalFileRecords,
            folderManifest: folderManifest,
            activeFolderID: activeFolderID,
            searchText: searchText,
            catalogSortOrder: catalogSortOrder,
            maximumFolderDepth: VaultFolderPresentationStore.maximumFolderDepth
        )
    }

    @ViewBuilder
    private func moveDestinationAction(
        for item: VaultPresentedContentReference
    ) -> some View {
        let currentFolderID = locationSnapshot.assignedFolderID(for: item)
        let hasDestination = currentFolderID != nil
            || locationSnapshot.sortedFolders.contains { $0.id != currentFolderID }

        if hasDestination {
            Button {
                requestItemMove(item)
            } label: {
                Label("Move", systemImage: "folder")
            }
        }
    }

    @ViewBuilder
    private func galleryItemCell(
        _ presentationItem: VaultGalleryPresentationItem,
        snapshot: VaultGalleryContentSnapshot
    ) -> some View {
        if let item = snapshot.sourceByID[presentationItem.id] {
            VaultGalleryItemTileView(
                item: presentationItem,
                thumbnail: thumbnail(for: item),
                selectionState: isSelecting ? selection.contains(item.id) : nil,
                action: { handleGalleryItemTap(item, snapshot: snapshot) }
            )
            .contextMenu {
                galleryItemContextMenu(item)
            }
            .task(id: item.id, priority: .utility) {
                await loadThumbnailIfNeeded(for: item)
            }
            .onAppear {
                thumbnailCache.markVisible(item.id)
            }
            .onDisappear {
                thumbnailCache.markHidden(item.id)
            }
        }
    }

    @ViewBuilder
    private func galleryItemContextMenu(
        _ item: VaultGalleryContentItem
    ) -> some View {
        Button {
            beginRename(item)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        .disabled(isWorking || itemRename.isActive)

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

            moveDestinationAction(for: presentedReference(for: item))

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

            moveDestinationAction(for: presentedReference(for: item))

            Button {
                showingVaultFiles = true
            } label: {
                Label("Manage File", systemImage: "doc")
            }
        }
    }

    private func beginRename(_ item: VaultGalleryContentItem) {
        guard !isWorking, session.hasActiveAccess else { return }
        switch item {
        case .photo(let record):
            guard let store else { return }
            itemRename.begin(photoStore: store, id: record.id, session: session, finished: finishRename)
        case .generalFile(let record):
            guard let generalFileStore else { return }
            itemRename.begin(fileStore: generalFileStore, id: record.id, session: session, finished: finishRename)
        }
    }

    @MainActor
    private func finishRename(_ failure: String?) async {
        let epoch = session.securityEpoch
        do {
            // Load both owners before publishing or reconciling membership.
            guard let store, let generalFileStore else { return }
            let photos = try await store.loadManifest().photos
            let files = try await generalFileStore.loadManifest().files
            try Task.checkCancellation()
            guard session.hasActiveAccess, session.securityEpoch == epoch else { return }
            records = photos
            generalFileRecords = files
            reconcileSelection()
            if let failure { message = failure }
        } catch {
            guard !Task.isCancelled, session.hasActiveAccess, session.securityEpoch == epoch else { return }
            message = failure ?? "The updated name could not be loaded. Lock and reopen the vault to check it."
        }
    }

    private func handleGalleryItemTap(
        _ item: VaultGalleryContentItem,
        snapshot: VaultGalleryContentSnapshot
    ) {
        if isSelecting {
            selection.toggle(item.id)
            return
        }

        switch item.openRoute {
        case .imagePreview, .videoPlayback:
            openMediaNavigation(startingAt: item, snapshot: snapshot)
        case .fileManagement:
            showingVaultFiles = true
        }
    }

    private func thumbnail(for item: VaultGalleryContentItem) -> UIImage? {
        thumbnailCache[item.id]
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

    private func initializeStores(expectedVaultID: UUID) async {
        guard !Task.isCancelled,
              let context = session.activeVaultContext(),
              context.id == expectedVaultID else { return }

        if store == nil {
            do {
                let createdStore = try VaultPhotoStore(vaultID: context.id, access: context.access)
                store = createdStore
                try await reload(using: createdStore)
                try Task.checkCancellation()
            } catch {
                store = nil
                guard !Task.isCancelled, session.activeVaultID == expectedVaultID else { return }
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
                try Task.checkCancellation()
            } catch {
                presentationStore = nil
                guard !Task.isCancelled, session.activeVaultID == expectedVaultID else { return }
                message = "The encrypted presentation store could not be opened."
            }
        }

        if generalFileStore == nil {
            do {
                let access = SessionGeneralFileAccess(capability: context.access)
                let createdStore = try VaultGeneralFileStore(vaultID: context.id, access: access)
                generalFileStore = createdStore
                generalFileRecords = try await createdStore.loadManifest().files
                try Task.checkCancellation()
            } catch {
                generalFileStore = nil
                guard !Task.isCancelled, session.activeVaultID == expectedVaultID else { return }
                message = "The encrypted file store could not be opened."
            }
        }

        await reconcilePresentationStore()
    }

    @MainActor
    private func reloadGeneralFiles() async {
        guard !Task.isCancelled,
              let generalFileStore,
              session.hasActiveAccess else { return }
        do {
            let loadedRecords = try await generalFileStore.loadManifest().files
            try Task.checkCancellation()
            guard session.hasActiveAccess else { return }
            generalFileRecords = loadedRecords
            let validIDs = Set(generalFileRecords.map(\.id))
            thumbnailCache.retainGeneralFiles(withIDs: validIDs)
            retainKnownThumbnailIDs()
            reconcileSelection()
            if isSelecting && visibleSelectableItems.isEmpty {
                leaveSelectionMode()
            }
            await reconcilePresentationStore()
        } catch is CancellationError {
            return
        } catch {
            guard session.hasActiveAccess else { return }
            message = "The encrypted file list could not be refreshed."
        }
    }

    @MainActor
    private func reconcilePresentationStore() async {
        guard !Task.isCancelled,
              let presentationStore,
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
            let loadedManifest = try await presentationStore.loadManifest()
            try Task.checkCancellation()
            guard session.hasActiveAccess else { return }
            folderManifest = loadedManifest
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
        folderActions.requestNewFolder()
    }

    private func requestFolderRename(id: UUID) {
        folderActions.requestRename(id: id, location: locationSnapshot)
    }

    private func requestFolderDeletion(id: UUID) {
        folderActions.requestDeletion(id: id, location: locationSnapshot)
    }

    private func requestItemMove(_ item: VaultPresentedContentReference) {
        folderActions.requestItemMove(item, location: locationSnapshot)
    }

    private func requestSelectionMove() {
        folderActions.requestSelectionMove(selectedPresentedReferences, location: locationSnapshot)
    }

    private func requestFolderMove(id: UUID) {
        if let failure = folderActions.requestFolderMove(id: id, location: locationSnapshot) {
            message = failure
        }
    }

    private func performMove(_ target: VaultGalleryMoveTarget, to folderID: UUID?) {
        switch target {
        case .item(let item):
            move(item, to: folderID)
        case .selection(let items):
            moveSelectedItems(items, to: folderID)
        case .folder(let folder):
            moveFolder(folder, to: folderID)
        }
    }

    private func saveFolderName() {
        guard let mutation = folderActions.nameMutation(parentID: activeFolderID),
              let presentationStore,
              !isWorking else { return }

        folderActions.dismissEditor()
        folderActions.clearNameDraft()
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                folderManifest = try await mutation.perform(using: presentationStore)
            } catch is CancellationError {
                return
            } catch {
                message = mutation.failureMessage(for: error)
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

    private func navigateToFolder(_ folderID: UUID?) {
        if let folderID,
           !folderManifest.folders.contains(where: { $0.id == folderID }) {
            return
        }
        guard !isWorking else { return }
        leaveSelectionMode()
        activeFolderID = folderID
    }

    private func moveFolder(_ folder: VaultFolderRecord, to parentID: UUID?) {
        guard let presentationStore, !isWorking else { return }
        let mutation = VaultGalleryFolderMutation.moveFolder(id: folder.id, parentID: parentID)
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                folderManifest = try await mutation.perform(using: presentationStore)
            } catch is CancellationError {
                return
            } catch {
                message = mutation.failureMessage(for: error)
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func move(
        _ item: VaultPresentedContentReference,
        to folderID: UUID?
    ) {
        guard let presentationStore, !isWorking else { return }
        let mutation = VaultGalleryFolderMutation.moveItem(item, folderID: folderID)
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                folderManifest = try await mutation.perform(using: presentationStore)
                selection.remove(selectionItem(for: item))
                if isSelecting && visibleSelectableItems.isEmpty {
                    leaveSelectionMode()
                }
            } catch is CancellationError {
                return
            } catch {
                message = mutation.failureMessage(for: error)
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func moveSelectedItems(
        _ items: Set<VaultPresentedContentReference>,
        to folderID: UUID?
    ) {
        guard let presentationStore, !items.isEmpty, !isWorking else { return }
        let destinationName = folderID.flatMap { destinationID in
            folderManifest.folders.first { $0.id == destinationID }?.name
        } ?? "Vault Root"
        let mutation = VaultGalleryFolderMutation.moveSelection(items, folderID: folderID)
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                folderManifest = try await mutation.perform(using: presentationStore)
                guard !Task.isCancelled else { return }
                let movedCount = items.count
                leaveSelectionMode()
                let noun = movedCount == 1 ? "item" : "items"
                message = "Moved \(movedCount) \(noun) to \(destinationName)."
            } catch is CancellationError {
                return
            } catch {
                message = mutation.failureMessage(for: error)
            }
        }
        if taskID == nil { isWorking = false }
    }

    private func deleteFolder(_ folder: VaultFolderRecord) {
        guard let presentationStore, !isWorking else { return }
        let mutation = VaultGalleryFolderMutation.deleteFolder(id: folder.id)
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                folderManifest = try await mutation.perform(using: presentationStore)
                if activeFolderID == folder.id {
                    activeFolderID = nil
                    leaveSelectionMode()
                }
            } catch is CancellationError {
                return
            } catch {
                message = mutation.failureMessage(for: error)
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
        guard let generalFileStore, let presentationStore,
              let destination = importDestination,
              destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch),
              !isWorking else { return }
        isWorking = true

        let taskID = session.startSensitiveTask { _ in
            var rootFallbackCount = 0
            defer {
                generalFileImportProgress = nil
                isWorking = false
            }
            do {
                let outcome = try await GeneralFileImportCoordinator.importFiles(
                    at: urls,
                    using: generalFileStore,
                    recordDidImport: { record in
                        let placed = try await destination.place(
                            VaultPresentedContentReference(kind: .generalFile, id: record.id)
                        ) { item, folderID in
                            try await presentationStore.move(item, to: folderID)
                        }
                        if !placed { rootFallbackCount += 1 }
                    }
                ) { progress in
                    generalFileImportProgress = progress
                }
                guard !Task.isCancelled,
                      destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch) else { return }
                await reloadGeneralFiles()
                message = GeneralFileImportPresentation.message(for: outcome)
                    + VaultImportDestination.recoveryMessage(rootCount: rootFallbackCount)
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be imported into this vault."
            }
        }
        if taskID == nil {
            generalFileImportProgress = nil
            isWorking = false
        }
    }

    private func reload(using store: VaultPhotoStore, reconcileFolders: Bool = true) async throws {
        let manifest = try await store.loadManifest()

        records = manifest.photos
        let validIDs = Set(manifest.photos.map(\.id))
        thumbnailCache.retainPhotos(withIDs: validIDs)
        retainKnownThumbnailIDs()
        reconcileSelection()

        if visibleSelectableItems.isEmpty {
            leaveSelectionMode()
        }
        if reconcileFolders { await reconcilePresentationStore() }
    }

    @MainActor
    private func handleImportEvent(
        _ event: PickedVaultPhotoEvent,
        destination: VaultImportDestination?
    ) async {
        guard let destination,
              destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch),
              let presentationStore else { return }
        switch event {
        case .started(let total):
            guard !isWorking else { return }
            isWorking = true
            importProgress = VaultImportProgress(mode: importMode, total: total)

        case .photo(let photo):
            await session.performSensitiveTask { capability in
                guard var progress = importProgress,
                      let store,
                      session.activeVaultID == capability.vaultID,
                      !Task.isCancelled else { return }
                do {
                    let record = try await store.importPhoto(
                        originalData: photo.originalData,
                        thumbnailData: photo.thumbnailData,
                        displayName: photo.displayName
                    )
                    let placed = try await destination.place(
                        VaultPresentedContentReference(kind: .photo, id: record.id)
                    ) { item, folderID in
                        try await presentationStore.move(item, to: folderID)
                    }
                    try Task.checkCancellation()
                    guard destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch) else { return }
                    progress.importedCount += 1
                    if !placed { progress.rootFallbackCount += 1 }
                    if placed, progress.mode == .move, let identifier = photo.sourceAssetIdentifier {
                        progress.identifiersToDelete.append(identifier)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    progress.failedCount += 1
                }
                importProgress = progress
            }

        case .video(let video):
            await session.performSensitiveTask { capability in
                guard var progress = importProgress,
                      let generalFileStore,
                      session.activeVaultID == capability.vaultID,
                      !Task.isCancelled else { return }
                do {
                    let record = try await generalFileStore.importFile(at: video.fileURL)
                    let placed = try await destination.place(
                        VaultPresentedContentReference(kind: .generalFile, id: record.id)
                    ) { item, folderID in
                        try await presentationStore.move(item, to: folderID)
                    }
                    try Task.checkCancellation()
                    guard destination.matches(vaultID: session.activeVaultID, securityEpoch: session.securityEpoch) else { return }
                    progress.importedCount += 1
                    if !placed { progress.rootFallbackCount += 1 }
                    if placed, progress.mode == .move,
                       let identifier = video.sourceAssetIdentifier {
                        progress.identifiersToDelete.append(identifier)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    progress.failedCount += 1
                }
                importProgress = progress
            }

        case .failed:
            importProgress?.failedCount += 1

        case .finished:
            showingPicker = false
            guard let progress = importProgress else {
                isWorking = false
                return
            }
            importProgress = nil
            await session.performSensitiveTask { capability in
                guard session.activeVaultID == capability.vaultID else { return }
                await finishImport(progress)
            }
            if !session.hasActiveAccess {
                isWorking = false
            }
        }
    }

    @MainActor
    private func finishImport(_ progress: VaultImportProgress) async {
        guard let store, session.isUnlocked, !Task.isCancelled else {
            isWorking = false
            return
        }

        do {
            // Refresh both content catalogs before pruning membership. A mixed
            // Photos batch can create photo and general-file (video) records.
            try await reload(using: store, reconcileFolders: false)
            await reloadGeneralFiles()
        } catch {
            guard !Task.isCancelled, session.hasActiveAccess else {
                isWorking = false
                return
            }
            message = "Items were encrypted, but the gallery could not be refreshed."
        }

        if progress.mode == .move, progress.importedCount > 0 {
            guard !Task.isCancelled, session.hasActiveAccess else {
                isWorking = false
                return
            }
            let allImportedPhotosAreDeletable =
                progress.identifiersToDelete.count == progress.importedCount
            let result: PhotoMoveResult
            if allImportedPhotosAreDeletable {
                session.beginSystemPhotoOperation()
                result = await PhotoLibraryDeletionService.deleteOriginals(
                    localIdentifiers: progress.identifiersToDelete
                )
                session.endSystemPhotoOperation()
                guard !Task.isCancelled, session.hasActiveAccess else {
                    isWorking = false
                    return
                }
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
                message = progress.rootFallbackCount > 0
                    ? "\(base) Originals were kept because folder placement was incomplete."
                    : "\(base) iOS did not delete every original, so KeyHollow treats this batch as copied."
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
        if progress.rootFallbackCount > 0 {
            message = (message ?? "")
                + VaultImportDestination.recoveryMessage(rootCount: progress.rootFallbackCount)
        }
        isWorking = false
    }

    @MainActor
    private func loadThumbnailIfNeeded(_ record: VaultPhotoRecord) async {
        guard thumbnailCache[.photo(record.id)] == nil,
              let store,
              let activeVaultID = session.activeVaultID,
              session.hasActiveAccess else { return }
        await session.performSensitiveTask { capability in
            guard capability.vaultID == activeVaultID,
                  let data = try? await store.loadThumbnail(record),
                  !Task.isCancelled,
                  let rendered = try? await thumbnailImageProcessor.decodeThumbnail(from: data),
                  !Task.isCancelled,
                  session.activeVaultID == activeVaultID else { return }

            thumbnailCache.insert(rendered.image, for: .photo(record.id))
        }
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
        guard thumbnailCache[.generalFile(record.id)] == nil,
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
                thumbnailCache.insert(renderedImage.image, for: .generalFile(record.id))
            } catch is CancellationError {
                return
            } catch {
                // A presentation preview must never block access to protected content.
                return
            }
        }
    }

    private func retainKnownThumbnailIDs() {
        let known = Set(records.map { VaultGallerySelection.Item.photo($0.id) })
            .union(generalFileRecords.map { VaultGallerySelection.Item.generalFile($0.id) })
        thumbnailCache.retainKnownItems(known)
    }

    private func importResultMessage(action: String, importedCount: Int, failedCount: Int) -> String {
        let noun = importedCount == 1 ? "item" : "items"
        if failedCount > 0 {
            let failedNoun = failedCount == 1 ? "item" : "items"
            return "\(action) \(importedCount) \(noun) into KeyHollow. \(failedCount) \(failedNoun) could not be imported."
        }
        return "\(action) \(importedCount) \(noun) into KeyHollow."
    }

    private func unreadableSelectionMessage(count: Int) -> String {
        let noun = count == 1 ? "item" : "items"
        return "No items were imported. \(count) selected \(noun) could not be read or exceeded the 100 MB video limit."
    }

    private func openMediaNavigation(
        startingAt source: VaultGalleryContentItem,
        snapshot: VaultGalleryContentSnapshot
    ) {
        guard !isWorking,
              !isSavingPreview,
              !isDeletingMedia,
              !isClosingMediaNavigation,
              let item = source.mediaNavigationItem else { return }

        do {
            mediaNavigationQueue = try snapshot.mediaNavigationQueue(
                startingAt: item.id
            )
            mediaNavigationSources = snapshot.mediaNavigationSourceByID
            previewMessage = nil
            failedMediaID = nil
            isClosingMediaNavigation = false
            isDeletingMedia = false
            isMediaImageZoomed = false
            showMediaChromeTemporarily()
            prepareSelectedMedia(id: item.id)
        } catch {
            message = "The media viewer could not be opened."
        }
    }

    private func selectMediaNavigationItem(_ id: VaultMediaNavigationID) {
        guard !isSavingPreview,
              !isDeletingMedia,
              !isClosingMediaNavigation,
              let queue = mediaNavigationQueue,
              isMediaNavigationContentReady(queue),
              queue.selectedID != id,
              let selectedQueue = try? queue.selecting(id) else { return }

        mediaNavigationQueue = selectedQueue
        previewMessage = nil
        failedMediaID = nil
        isMediaImageZoomed = false
        showMediaChromeTemporarily()
        prepareSelectedMedia(id: id)
    }

    private func toggleMediaChrome() {
        guard !isSavingPreview, !isDeletingMedia, !isClosingMediaNavigation else {
            return
        }
        if isMediaChromeVisible {
            mediaChromeHideTask?.cancel()
            mediaChromeHideTask = nil
            isMediaChromeVisible = false
        } else {
            showMediaChromeTemporarily()
        }
    }

    private func showMediaChromeTemporarily() {
        mediaChromeHideTask?.cancel()
        isMediaChromeVisible = true
        mediaChromeHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !isSavingPreview,
                  !isDeletingMedia,
                  !isClosingMediaNavigation,
                  mediaNavigationQueue != nil else { return }
            isMediaChromeVisible = false
            mediaChromeHideTask = nil
        }
    }

    private func resetMediaChrome() {
        mediaChromeHideTask?.cancel()
        mediaChromeHideTask = nil
        isMediaChromeVisible = true
    }

    private func retryMediaNavigationItem(_ id: VaultMediaNavigationID) {
        guard !isSavingPreview,
              !isDeletingMedia,
              !isClosingMediaNavigation,
              mediaNavigationQueue?.selectedID == id else { return }
        previewMessage = nil
        failedMediaID = nil
        prepareSelectedMedia(id: id)
    }

    private func prepareSelectedMedia(id: VaultMediaNavigationID) {
        failedMediaID = nil
        isMediaImageZoomed = false
        mediaNavigationGeneration &+= 1
        let generation = mediaNavigationGeneration
        let retiringTask = mediaNavigationTask
        mediaNavigationTask = nil
        retiringTask?.cancel()
        imagePreview.dismiss()
        requestVideoPlaybackStop()

        mediaNavigationTask = Task { @MainActor in
            if let retiringTask {
                await retiringTask.value
            }
            await imagePreview.dismissAndWait()
            await waitForVideoPlaybackStop()

            guard !Task.isCancelled,
                  isCurrentMediaSelection(id, generation: generation),
                  let source = mediaNavigationSources[id],
                  let descriptor = source.mediaNavigationItem,
                  session.hasActiveAccess else { return }

            switch descriptor.kind {
            case .image:
                await prepareMediaImage(
                    source,
                    descriptor: descriptor,
                    generation: generation
                )
            case .video:
                await prepareMediaVideo(
                    source,
                    descriptor: descriptor,
                    generation: generation
                )
            }
        }
    }

    private func prepareMediaImage(
        _ source: VaultGalleryContentItem,
        descriptor: VaultMediaNavigationItem,
        generation: UInt64
    ) async {
        await session.performSensitiveTask { _ in
            do {
                switch source {
                case .photo(let record):
                    guard let store else {
                        throw VaultMediaNavigationPresentationError.storeUnavailable
                    }
                    try await imagePreview.prepare(
                        id: descriptor.id,
                        displayName: descriptor.title,
                        processor: previewImageProcessor,
                        loadOriginalData: {
                            try await store.loadPhoto(record)
                        }
                    )
                case .generalFile(let record):
                    guard let generalFileStore else {
                        throw VaultMediaNavigationPresentationError.storeUnavailable
                    }
                    try await imagePreview.prepare(
                        id: descriptor.id,
                        displayName: descriptor.title,
                        processor: previewImageProcessor,
                        loadOriginalData: {
                            try await generalFileStore.loadFile(record)
                        }
                    )
                }
            } catch is CancellationError {
                return
            } catch VaultPhotoStore.StoreError.originalTooLarge {
                guard isCurrentMediaSelection(
                    descriptor.id,
                    generation: generation
                ) else { return }
                failedMediaID = descriptor.id
                previewMessage = "This legacy photo is larger than KeyHollow's current safe open-size limit. It remains encrypted and can be deleted, moved, or included in a compatibility export."
            } catch {
                guard isCurrentMediaSelection(
                    descriptor.id,
                    generation: generation
                ) else { return }
                failedMediaID = descriptor.id
                previewMessage = "The image could not be authenticated, validated, and opened."
            }
        }
    }

    private func prepareMediaVideo(
        _ source: VaultGalleryContentItem,
        descriptor: VaultMediaNavigationItem,
        generation: UInt64
    ) async {
        guard case .generalFile(let record) = source,
              let generalFileStore else {
            if isCurrentMediaSelection(descriptor.id, generation: generation) {
                failedMediaID = descriptor.id
                previewMessage = "The encrypted video store is unavailable."
            }
            return
        }

        await session.performSensitiveTask(
            onSessionRevocation: {
                // Session retirement is authoritative. SwiftUI may remove the
                // gallery before its security-epoch observer runs, so signal
                // both halves of the protected playback lifetime here.
                videoPlaybackSession.requestStop()
                videoPlayback.dismiss()
            }
        ) { _ in
            do {
                try await videoPlayback.prepare(record, using: generalFileStore)
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentMediaSelection(
                    descriptor.id,
                    generation: generation
                ) else { return }
                failedMediaID = descriptor.id
                previewMessage = "The video could not be authenticated, validated, and opened."
            }
        }
    }

    private func isCurrentMediaSelection(
        _ id: VaultMediaNavigationID,
        generation: UInt64
    ) -> Bool {
        !Task.isCancelled
            && mediaNavigationGeneration == generation
            && mediaNavigationQueue?.selectedID == id
            && !isClosingMediaNavigation
    }

    private func isMediaNavigationContentReady(
        _ queue: VaultMediaNavigationQueue
    ) -> Bool {
        if failedMediaID == queue.selectedID {
            return true
        }

        switch queue.currentItem.kind {
        case .image:
            return imagePreview.active?.id == queue.selectedID
        case .video:
            guard let active = videoPlayback.active else { return false }
            return VaultGalleryContentItem.generalFile(active.source)
                .mediaNavigationID == queue.selectedID
        }
    }

    private func delete(_ record: VaultPhotoRecord) {
        guard let store, !isWorking else { return }
        imagePreview.dismiss()
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
        imagePreview.dismiss()
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await generalFileStore.delete([record])
                generalFileRecords = try await generalFileStore.loadManifest().files
                thumbnailCache.remove(.generalFile(record.id))
                await reconcilePresentationStore()
            } catch is CancellationError {
                return
            } catch {
                message = "The file could not be deleted from the vault."
            }
        }
    }

    private func saveCurrentMediaImage() {
        guard !isSavingPreview,
              !isDeletingMedia,
              !isClosingMediaNavigation,
              let selectedID = mediaNavigationQueue?.selectedID,
              let active = imagePreview.active,
              active.id == selectedID else { return }

        let saveGeneration = mediaNavigationGeneration
        let preview = active.preview
        isSavingPreview = true

        let taskID = session.startSensitiveTask { _ in
            session.beginSystemPhotoOperation()
            defer {
                session.endSystemPhotoOperation()
                if mediaNavigationGeneration == saveGeneration {
                    imageSaveTaskID = nil
                    isSavingPreview = false
                }
            }

            let result = await PhotoLibrarySaveService.savePhoto(
                preview.originalData
            )
            guard isCurrentMediaSelection(
                selectedID,
                generation: saveGeneration
            ) else { return }

            switch result {
            case .saved:
                previewMessage = "Saved to Photos. The encrypted vault copy was kept."
            case .permissionDenied:
                previewMessage = "Allow KeyHollow to add photos in iPhone Settings, then try again."
            case .failed:
                previewMessage = "This image could not be saved to Photos."
            }
        }
        imageSaveTaskID = taskID
        if taskID == nil { isSavingPreview = false }
    }

    private func handleMediaPlaybackFailure(for id: VaultMediaNavigationID) {
        guard mediaNavigationQueue?.selectedID == id,
              !isClosingMediaNavigation else { return }
        requestVideoPlaybackStop()
        failedMediaID = id
        previewMessage = "The video stopped because iOS could not continue secure playback."
    }

    private func requestVideoPlaybackStop() {
        // The module-owned session must detach AVKit and acknowledge its player
        // lease before the coordinator may discard the protected plaintext.
        videoPlaybackSession.requestStop()
        videoPlayback.dismiss()
    }

    private func waitForVideoPlaybackStop() async {
        await videoPlaybackSession.stopAndWait()
        await videoPlayback.dismissAndWait()
    }

    private func beginMediaNavigationDismissal() {
        guard mediaNavigationQueue != nil,
              !isSavingPreview,
              !isDeletingMedia,
              !isClosingMediaNavigation else { return }

        isClosingMediaNavigation = true
        resetMediaChrome()
        mediaNavigationGeneration &+= 1
        let dismissalGeneration = mediaNavigationGeneration
        let retiringTask = mediaNavigationTask
        mediaNavigationTask = nil
        retiringTask?.cancel()
        imagePreview.dismiss()
        requestVideoPlaybackStop()

        mediaNavigationTask = Task { @MainActor in
            if let retiringTask {
                await retiringTask.value
            }
            await imagePreview.dismissAndWait()
            await waitForVideoPlaybackStop()
            guard mediaNavigationGeneration == dismissalGeneration else { return }
            clearMediaNavigationState()
        }
    }

    private func deleteCurrentMedia() {
        guard !isDeletingMedia,
              !isSavingPreview,
              !isClosingMediaNavigation,
              let queue = mediaNavigationQueue,
              let source = mediaNavigationSources[queue.selectedID] else { return }

        isDeletingMedia = true
        mediaNavigationGeneration &+= 1
        let deletionGeneration = mediaNavigationGeneration
        let deletingID = queue.selectedID
        let retiringTask = mediaNavigationTask
        mediaNavigationTask = nil
        retiringTask?.cancel()
        imagePreview.dismiss()
        requestVideoPlaybackStop()

        mediaNavigationTask = Task { @MainActor in
            if let retiringTask {
                await retiringTask.value
            }
            await imagePreview.dismissAndWait()
            await waitForVideoPlaybackStop()

            guard !Task.isCancelled,
                  mediaNavigationGeneration == deletionGeneration,
                  mediaNavigationQueue?.selectedID == deletingID,
                  session.hasActiveAccess else { return }

            var didDelete = false
            var failureMessage: String?
            await session.performSensitiveTask { _ in
                do {
                    switch source {
                    case .photo(let record):
                        guard let store else {
                            throw VaultMediaNavigationPresentationError.storeUnavailable
                        }
                        try await store.delete(record)
                        try await reload(using: store)
                    case .generalFile(let record):
                        guard let generalFileStore else {
                            throw VaultMediaNavigationPresentationError.storeUnavailable
                        }
                        try await generalFileStore.delete([record])
                        generalFileRecords = try await generalFileStore.loadManifest().files
                        thumbnailCache.remove(.generalFile(record.id))
                        await reconcilePresentationStore()
                    }
                    didDelete = true
                } catch is CancellationError {
                    return
                } catch {
                    failureMessage = source.openRoute == .videoPlayback
                        ? "The video could not be deleted from the vault."
                        : "The image could not be deleted from the vault."
                }
            }

            guard !Task.isCancelled,
                  mediaNavigationGeneration == deletionGeneration,
                  mediaNavigationQueue?.selectedID == deletingID else { return }

            mediaNavigationTask = nil
            isDeletingMedia = false

            guard didDelete else {
                previewMessage = failureMessage
                    ?? "The item could not be deleted from the vault."
                prepareSelectedMedia(id: deletingID)
                return
            }

            mediaNavigationSources.removeValue(forKey: deletingID)
            guard let remainingQueue = queue.removing(deletingID) else {
                clearMediaNavigationState()
                return
            }

            mediaNavigationQueue = remainingQueue
            prepareSelectedMedia(id: remainingQueue.selectedID)
        }
    }

    private func resetMediaNavigationAndWait() async {
        resetMediaChrome()
        mediaNavigationGeneration &+= 1
        let retiringTask = mediaNavigationTask
        let retiringSaveTaskID = imageSaveTaskID
        mediaNavigationTask = nil
        imageSaveTaskID = nil
        retiringTask?.cancel()
        imagePreview.dismiss()
        requestVideoPlaybackStop()
        mediaNavigationQueue = nil

        if let retiringSaveTaskID {
            await session.cancelSensitiveTaskAndWait(retiringSaveTaskID)
        }
        if let retiringTask {
            await retiringTask.value
        }
        await imagePreview.dismissAndWait()
        await waitForVideoPlaybackStop()
        isSavingPreview = false
        clearMediaNavigationState()
    }

    private func cancelMediaNavigationForLifecycle() {
        resetMediaChrome()
        mediaNavigationGeneration &+= 1
        mediaNavigationTask?.cancel()
        mediaNavigationTask = nil
        if let imageSaveTaskID {
            session.cancelSensitiveTask(imageSaveTaskID)
            self.imageSaveTaskID = nil
        }
        imagePreview.dismiss()
        requestVideoPlaybackStop()
        mediaNavigationQueue = nil
        mediaNavigationSources = [:]
        failedMediaID = nil
        isClosingMediaNavigation = false
        isDeletingMedia = false
        isSavingPreview = false
        isMediaImageZoomed = false
        previewMessage = nil
    }

    private func clearMediaNavigationState() {
        resetMediaChrome()
        mediaNavigationTask = nil
        if let imageSaveTaskID {
            session.cancelSensitiveTask(imageSaveTaskID)
            self.imageSaveTaskID = nil
        }
        mediaNavigationQueue = nil
        mediaNavigationSources = [:]
        failedMediaID = nil
        isClosingMediaNavigation = false
        isDeletingMedia = false
        isSavingPreview = false
        isMediaImageZoomed = false
        imagePreview.dismiss()
        requestVideoPlaybackStop()
        previewMessage = nil
    }

    private var selectedPhotoRecords: [VaultPhotoRecord] {
        locationSnapshot.visiblePhotoRecords.filter { selection.contains(.photo($0.id)) }
    }

    private var selectedGeneralFileRecords: [VaultGeneralFileRecord] {
        locationSnapshot.visibleGeneralFileRecords.filter { selection.contains(.generalFile($0.id)) }
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
        locationSnapshot.filteredVisibleGallerySnapshot.selectableItems
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
            do {
                let prepared = try await generalFileStore.prepareExport(files)
                guard !Task.isCancelled else {
                    await generalFileStore.discardExport(prepared)
                    isWorking = false
                    return
                }
                session.beginSystemInteraction()
                generalFileExport = prepared
                await waitForGeneralFileExportDismissal()
                // This task stays session-registered until plaintext cleanup,
                // making lock/deletion barriers observe the actual lifetime of
                // the decrypted export directory.
                await generalFileStore.discardExport(prepared)
                if generalFileExport?.id == prepared.id {
                    generalFileExport = nil
                    session.endSystemInteraction()
                }
            } catch is CancellationError {
                // Preparation owns cleanup when cancellation precedes a result.
            } catch {
                message = "The selected files could not be authenticated and exported."
            }
            generalFileExportTaskID = nil
            isWorking = false
        }
        generalFileExportTaskID = taskID
        if taskID == nil { isWorking = false }
    }

    private func finishGeneralFileExport(_ prepared: PreparedGeneralFileExport) {
        generalFileExport = nil
        session.endSystemInteraction()
        guard let taskID = generalFileExportTaskID else { return }
        session.cancelSensitiveTask(taskID)
    }

    private func waitForGeneralFileExportDismissal() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                return
            }
        }
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

