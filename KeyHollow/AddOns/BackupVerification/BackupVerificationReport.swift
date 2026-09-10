import Foundation

/// A display-safe, immutable summary of one completed backup verification.
///
/// Its primitive fields describe the outcome without carrying any protected
/// data or operational capability. The application may publish it only after
/// authentication is complete and temporary verification material is gone.
public struct BackupVerificationReport: Equatable, Sendable {
    public let displayName: String
    public let archiveByteCount: UInt64
    public let sourceVaultCreatedAt: Date
    public let verifiedAt: Date
    public let catalogVersion: Int
    public let photoCount: Int
    public let generalFileCount: Int
    public let authenticatedEntryCount: Int
    public let legacyOversizedPhotoCount: Int

    public init(
        displayName: String,
        archiveByteCount: UInt64,
        sourceVaultCreatedAt: Date,
        verifiedAt: Date,
        catalogVersion: Int,
        photoCount: Int,
        generalFileCount: Int,
        authenticatedEntryCount: Int,
        legacyOversizedPhotoCount: Int
    ) {
        self.displayName = displayName
        self.archiveByteCount = archiveByteCount
        self.sourceVaultCreatedAt = sourceVaultCreatedAt
        self.verifiedAt = verifiedAt
        self.catalogVersion = catalogVersion
        self.photoCount = photoCount
        self.generalFileCount = generalFileCount
        self.authenticatedEntryCount = authenticatedEntryCount
        self.legacyOversizedPhotoCount = legacyOversizedPhotoCount
    }

    public var status: BackupVerificationStatus {
        guard legacyOversizedPhotoCount > 0 else { return .verified }
        return .verifiedWithLegacyLimitations(
            oversizedPhotoCount: legacyOversizedPhotoCount
        )
    }
}

/// The status shown after authentication. A legacy oversized item never
/// receives the same wording as content that completed current item-level
/// verification.
public enum BackupVerificationStatus: Equatable, Sendable {
    case verified
    case verifiedWithLegacyLimitations(oversizedPhotoCount: Int)
}

/// Pure presentation text derived only from the sanitized report value. Keeping
/// these claims centralized prevents UI call sites from overstating what the
/// archive validator proved.
public enum BackupVerificationPresentationPolicy {
    public static let readOnlyDisclosure =
        "Verification checks the selected backup without installing a vault."

    public static func compatibilityDisclosure(
        for report: BackupVerificationReport
    ) -> String {
        let contentSupport: String
        if report.catalogVersion == 1 {
            contentSupport = "This legacy payload catalog preserves photos only."
        } else {
            contentSupport = "This payload catalog can preserve photos and general files."
        }
        return contentSupport
            + " Folder names and folder membership are not preserved."
    }

    public static func statusTitle(
        for report: BackupVerificationReport
    ) -> String {
        switch report.status {
        case .verified:
            "Backup verified"
        case .verifiedWithLegacyLimitations:
            "Backup authenticated with limitations"
        }
    }

    public static func statusDetail(
        for report: BackupVerificationReport
    ) -> String {
        switch report.status {
        case .verified:
            "All supported archived photos and files passed the current "
                + "verification checks."
        case .verifiedWithLegacyLimitations:
            "Archive authentication passed. One or more legacy photos could "
                + "not complete current item-level verification."
        }
    }

    public static func legacyLimitationDisclosure(
        for report: BackupVerificationReport
    ) -> String? {
        guard case let .verifiedWithLegacyLimitations(oversizedPhotoCount) =
                report.status else {
            return nil
        }
        let noun = oversizedPhotoCount == 1 ? "photo" : "photos"
        return "\(oversizedPhotoCount) legacy \(noun) exceed the current "
            + "open-size limit. Their encrypted bytes and archive digests "
            + "were authenticated, but full item opening and validation "
            + "were not performed."
    }

    public static func photoCountDescription(
        for report: BackupVerificationReport
    ) -> String {
        countDescription(report.photoCount, singular: "photo", plural: "photos")
    }

    public static func generalFileCountDescription(
        for report: BackupVerificationReport
    ) -> String {
        countDescription(
            report.generalFileCount,
            singular: "general file",
            plural: "general files"
        )
    }

    public static func authenticatedEntryCountDescription(
        for report: BackupVerificationReport
    ) -> String {
        countDescription(
            report.authenticatedEntryCount,
            singular: "authenticated archive entry",
            plural: "authenticated archive entries"
        )
    }

    public static func formattedArchiveByteCount(
        _ byteCount: UInt64
    ) -> String {
        guard byteCount <= UInt64(Int64.max) else {
            return "\(byteCount) bytes"
        }
        return ByteCountFormatter.string(
            fromByteCount: Int64(byteCount),
            countStyle: .file
        )
    }

    private static func countDescription(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
