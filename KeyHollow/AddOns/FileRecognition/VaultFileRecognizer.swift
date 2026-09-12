import Foundation

public struct RecognizedVaultFile: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public protocol VaultFileRecognizing: Sendable {
    func recognize(_ url: URL) -> RecognizedVaultFile?
}

public struct KHVaultFileRecognizer: VaultFileRecognizing {
    public static let filenameExtension = "khvault"

    public init() {}

    public func recognize(_ url: URL) -> RecognizedVaultFile? {
        guard url.isFileURL,
              url.pathExtension.caseInsensitiveCompare(Self.filenameExtension) == .orderedSame else {
            return nil
        }

        return RecognizedVaultFile(url: url)
    }
}

public struct StagedVaultFile: Equatable, Sendable {
    public let url: URL
    public let displayName: String
    public let byteCount: UInt64
    private let cleanupLease: StagedVaultFileCleanupLease

    fileprivate init(
        url: URL,
        displayName: String,
        byteCount: UInt64,
        directoryLease: VaultFileIngressDirectoryLease
    ) {
        self.url = url
        self.displayName = displayName
        self.byteCount = byteCount
        cleanupLease = StagedVaultFileCleanupLease(directoryLease: directoryLease)
    }

    public func discard(using fileManager: FileManager = .default) {
        try? discardChecked(using: fileManager)
    }

    /// Removes the complete ingress-owned lease and reports cleanup failure to
    /// callers that must not publish success while temporary data remains.
    public func discardChecked(using fileManager: FileManager = .default) throws {
        try cleanupLease.discardChecked(using: fileManager)
    }

    public static func == (lhs: StagedVaultFile, rhs: StagedVaultFile) -> Bool {
        lhs.url == rhs.url
            && lhs.displayName == rhs.displayName
            && lhs.byteCount == rhs.byteCount
    }
}

/// Reference ownership keeps cleanup attached to every value copy. If a
/// cancellation races the handoff into UI state, releasing the final value
/// still retries removal of the complete ingress-owned directory.
private final class StagedVaultFileCleanupLease: @unchecked Sendable {
    private let cleanupRoot: URL
    private let lock = NSLock()
    private var ownsCleanupRoot = true
    private var directoryLease: VaultFileIngressDirectoryLease?

    init(directoryLease: VaultFileIngressDirectoryLease) {
        cleanupRoot = directoryLease.directoryURL
        self.directoryLease = directoryLease
    }

    deinit {
        try? discardChecked()
    }

    func discardChecked(using fileManager: FileManager = .default) throws {
        lock.lock()
        defer { lock.unlock() }
        guard ownsCleanupRoot else { return }
        do {
            try fileManager.removeItem(at: cleanupRoot)
        } catch {
            let cocoaError = error as NSError
            guard cocoaError.domain == NSCocoaErrorDomain,
                  cocoaError.code == NSFileNoSuchFileError else {
                throw error
            }
        }
        ownsCleanupRoot = false
        directoryLease = nil
    }
}

/// Prevents one live import from being mistaken for crash debris by another
/// import in the same process. A later ingress removes only canonical UUID
/// directories that have no live lease, so restart-and-retry converges stale
/// encrypted copies without widening deletion beyond the add-on-owned root.
fileprivate final class VaultFileIngressDirectoryLease: @unchecked Sendable {
    let directoryURL: URL

    private let rootKey: String
    private let identifier: String
    private let registry: VaultFileIngressDirectoryRegistry

    init(
        directoryURL: URL,
        rootKey: String,
        identifier: String,
        registry: VaultFileIngressDirectoryRegistry
    ) {
        self.directoryURL = directoryURL
        self.rootKey = rootKey
        self.identifier = identifier
        self.registry = registry
    }

    deinit {
        registry.release(rootKey: rootKey, identifier: identifier)
    }
}

fileprivate final class VaultFileIngressDirectoryRegistry: @unchecked Sendable {
    static let shared = VaultFileIngressDirectoryRegistry()

    private let lock = NSLock()
    private var activeIdentifiersByRoot: [String: Set<String>] = [:]

    func acquire(
        at rootURL: URL,
        fileManager: FileManager
    ) throws -> VaultFileIngressDirectoryLease {
        let root = rootURL.standardizedFileURL
        let identifier = UUID().uuidString.lowercased()

        lock.lock()
        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            let rootValues = try root.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ])
            guard rootValues.isDirectory == true,
                  rootValues.isSymbolicLink != true else {
                throw VaultFileIngressError.unavailable
            }
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: root.path
            )
            var protectedRoot = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedRoot.setResourceValues(values)

            let rootKey = root.resolvingSymlinksInPath().path
            try removeAbandonedItems(
                at: root,
                preserving: activeIdentifiersByRoot[rootKey] ?? [],
                fileManager: fileManager
            )
            activeIdentifiersByRoot[rootKey, default: []].insert(identifier)
            lock.unlock()
            return VaultFileIngressDirectoryLease(
                directoryURL: root.appendingPathComponent(identifier, isDirectory: true),
                rootKey: rootKey,
                identifier: identifier,
                registry: self
            )
        } catch {
            lock.unlock()
            throw error
        }
    }

    fileprivate func release(rootKey: String, identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        activeIdentifiersByRoot[rootKey]?.remove(identifier)
        if activeIdentifiersByRoot[rootKey]?.isEmpty == true {
            activeIdentifiersByRoot.removeValue(forKey: rootKey)
        }
    }

    private func removeAbandonedItems(
        at rootURL: URL,
        preserving activeIdentifiers: Set<String>,
        fileManager: FileManager
    ) throws {
        let items = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        for itemURL in items {
            let name = itemURL.lastPathComponent
            guard Self.isCanonicalIngressIdentifier(name),
                  !activeIdentifiers.contains(name) else {
                continue
            }
            let itemValues = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ])
            guard itemValues.isDirectory == true,
                  itemValues.isSymbolicLink != true else {
                continue
            }
            try fileManager.removeItem(at: itemURL)
        }
    }

    private static func isCanonicalIngressIdentifier(_ value: String) -> Bool {
        guard let identifier = UUID(uuidString: value) else { return false }
        return identifier.uuidString.lowercased() == value
    }
}

public enum VaultFileIngressError: Error, Equatable {
    case unsupportedFile
    case insufficientStorage
    case unavailable
}

/// Sanitized byte progress for copying an incoming archive into KeyHollow's
/// protected temporary storage. No source path or vault metadata crosses the
/// add-on boundary.
public struct VaultFileIngressProgress: Equatable, Sendable {
    public let completedByteCount: UInt64
    public let totalByteCount: UInt64

    public init(completedByteCount: UInt64, totalByteCount: UInt64) {
        self.totalByteCount = totalByteCount
        self.completedByteCount = min(completedByteCount, totalByteCount)
    }

    public var fractionCompleted: Double {
        guard totalByteCount > 0 else { return 0 }
        return Double(completedByteCount) / Double(totalByteCount)
    }
}

/// Owns the short-lived Files-provider permission and immediately copies an
/// incoming vault into app-controlled, protected temporary storage.
public struct KHVaultFileIngress {
    private static let requiredHeadroom: Int64 = 67_108_864

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func stageIfRecognized(
        _ sourceURL: URL,
        progress: (@Sendable (VaultFileIngressProgress) -> Void)? = nil
    ) throws -> StagedVaultFile? {
        guard let recognized = KHVaultFileRecognizer().recognize(sourceURL) else {
            return nil
        }
        return try stage(recognized, progress: progress)
    }

    public func stage(
        _ recognizedFile: RecognizedVaultFile,
        progress: (@Sendable (VaultFileIngressProgress) -> Void)? = nil
    ) throws -> StagedVaultFile {
        let sourceURL = recognizedFile.url
        let displayName = sourceURL.lastPathComponent
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var coordinationError: NSError?
        var stagedResult: Result<StagedVaultFile, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                stagedResult = .success(
                    try stageCoordinatedFile(
                        at: coordinatedURL,
                        displayName: displayName,
                        progress: progress
                    )
                )
            } catch {
                stagedResult = .failure(error)
            }
        }

        if coordinationError != nil {
            throw VaultFileIngressError.unavailable
        }
        guard let stagedResult else {
            throw VaultFileIngressError.unavailable
        }
        do {
            return try stagedResult.get()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VaultFileIngressError {
            throw error
        } catch {
            throw VaultFileIngressError.unavailable
        }
    }

    private func stageCoordinatedFile(
        at sourceURL: URL,
        displayName: String,
        progress: (@Sendable (VaultFileIngressProgress) -> Void)?
    ) throws -> StagedVaultFile {
        guard sourceURL.pathExtension.caseInsensitiveCompare(
            KHVaultFileRecognizer.filenameExtension
        ) == .orderedSame else {
            throw VaultFileIngressError.unsupportedFile
        }

        let sourceValues = try sourceURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ])
        guard sourceValues.isRegularFile == true,
              sourceValues.isSymbolicLink != true,
              let fileSize = sourceValues.fileSize,
              fileSize > 0 else {
            throw VaultFileIngressError.unsupportedFile
        }

        let sourceByteCount = UInt64(fileSize)
        guard sourceByteCount <= UInt64(Int64.max) else {
            throw VaultFileIngressError.unsupportedFile
        }
        let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "KeyHollowPortableImports",
            isDirectory: true
        )
        let directoryLease = try VaultFileIngressDirectoryRegistry.shared.acquire(
            at: stagingRoot,
            fileManager: fileManager
        )
        let sourceSize = Int64(sourceByteCount)
        let capacityValues = try fileManager.temporaryDirectory.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]
        )
        let available = capacityValues.volumeAvailableCapacityForImportantUsage ??
            Int64(capacityValues.volumeAvailableCapacity ?? 0)
        let doubled = sourceSize.multipliedReportingOverflow(by: 2)
        let withHeadroom = doubled.partialValue.addingReportingOverflow(
            Self.requiredHeadroom
        )
        guard !doubled.overflow,
              !withHeadroom.overflow,
              available >= withHeadroom.partialValue else {
            throw VaultFileIngressError.insufficientStorage
        }

        let importRoot = directoryLease.directoryURL
        do {
            try fileManager.createDirectory(
                at: importRoot,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var protectedRoot = importRoot
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedRoot.setResourceValues(values)

            let destination = importRoot.appendingPathComponent("Selected.khvault")
            try copyProtectedFile(
                from: sourceURL,
                to: destination,
                byteCount: sourceByteCount,
                progress: progress
            )
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destination.path
            )
            var protectedDestination = destination
            var destinationProtectionValues = URLResourceValues()
            destinationProtectionValues.isExcludedFromBackup = true
            try protectedDestination.setResourceValues(destinationProtectionValues)

            let postCopySourceValues = try URL(fileURLWithPath: sourceURL.path).resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            let destinationValues = try URL(fileURLWithPath: destination.path).resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard postCopySourceValues.isRegularFile == true,
                  postCopySourceValues.isSymbolicLink != true,
                  postCopySourceValues.fileSize == fileSize,
                  destinationValues.isRegularFile == true,
                  destinationValues.isSymbolicLink != true,
                  destinationValues.fileSize == fileSize else {
                throw VaultFileIngressError.unavailable
            }
            return StagedVaultFile(
                url: destination,
                displayName: displayName,
                byteCount: sourceByteCount,
                directoryLease: directoryLease
            )
        } catch {
            try? fileManager.removeItem(at: importRoot)
            throw error
        }
    }

    private func copyProtectedFile(
        from sourceURL: URL,
        to destinationURL: URL,
        byteCount: UInt64,
        progress: (@Sendable (VaultFileIngressProgress) -> Void)?
    ) throws {
        guard fileManager.createFile(
            atPath: destinationURL.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw VaultFileIngressError.unavailable
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        let destinationHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        let chunkByteCount = 1_048_576
        var copiedByteCount: UInt64 = 0
        progress?(VaultFileIngressProgress(
            completedByteCount: 0,
            totalByteCount: byteCount
        ))

        while copiedByteCount < byteCount {
            try Task.checkCancellation()
            let remainingByteCount = byteCount - copiedByteCount
            let requestedByteCount = Int(min(UInt64(chunkByteCount), remainingByteCount))
            guard let chunk = try sourceHandle.read(upToCount: requestedByteCount),
                  !chunk.isEmpty else {
                throw VaultFileIngressError.unavailable
            }
            try destinationHandle.write(contentsOf: chunk)
            copiedByteCount += UInt64(chunk.count)
            progress?(VaultFileIngressProgress(
                completedByteCount: copiedByteCount,
                totalByteCount: byteCount
            ))
        }

        try Task.checkCancellation()
        let trailingByte = try sourceHandle.read(upToCount: 1) ?? Data()
        guard trailingByte.isEmpty else {
            throw VaultFileIngressError.unavailable
        }
        try destinationHandle.synchronize()
    }
}
