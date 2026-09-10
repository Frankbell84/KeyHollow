import Foundation
import XCTest
@testable import KeyHollowBackupVerificationAddOn

final class VaultBackupVerificationAddOnTests: XCTestCase {
    func testReportExposesOnlyImmutablePresentationValues() {
        let report = makeReport()
        let storedFieldNames = Set(
            Mirror(reflecting: report).children.compactMap(\.label)
        )

        XCTAssertEqual(report.displayName, "Family Backup.khvault")
        XCTAssertEqual(report.archiveByteCount, 12_345)
        XCTAssertEqual(
            report.sourceVaultCreatedAt,
            Date(timeIntervalSinceReferenceDate: 100)
        )
        XCTAssertEqual(
            report.verifiedAt,
            Date(timeIntervalSinceReferenceDate: 200)
        )
        XCTAssertEqual(report.catalogVersion, 3)
        XCTAssertEqual(report.photoCount, 7)
        XCTAssertEqual(report.generalFileCount, 2)
        XCTAssertEqual(report.authenticatedEntryCount, 18)
        XCTAssertEqual(report.legacyOversizedPhotoCount, 0)
        XCTAssertEqual(storedFieldNames, [
            "displayName",
            "archiveByteCount",
            "sourceVaultCreatedAt",
            "verifiedAt",
            "catalogVersion",
            "photoCount",
            "generalFileCount",
            "authenticatedEntryCount",
            "legacyOversizedPhotoCount"
        ])
    }

    func testCurrentArchiveReceivesVerifiedStatus() {
        let report = makeReport(legacyOversizedPhotoCount: 0)

        XCTAssertEqual(report.status, .verified)
        XCTAssertEqual(
            BackupVerificationPresentationPolicy.statusTitle(for: report),
            "Backup verified"
        )
        XCTAssertTrue(
            BackupVerificationPresentationPolicy.statusDetail(for: report)
                .contains("passed the current verification checks")
        )
    }

    func testLegacyOversizedPhotoIsNotDescribedAsFullyVerified() {
        let report = makeReport(legacyOversizedPhotoCount: 1)
        let detail = BackupVerificationPresentationPolicy.statusDetail(for: report)
        let disclosure = BackupVerificationPresentationPolicy
            .legacyLimitationDisclosure(for: report)

        XCTAssertEqual(
            report.status,
            .verifiedWithLegacyLimitations(oversizedPhotoCount: 1)
        )
        XCTAssertEqual(
            BackupVerificationPresentationPolicy.statusTitle(for: report),
            "Backup authenticated with limitations"
        )
        XCTAssertTrue(detail.contains("could not complete current item-level verification"))
        XCTAssertTrue(disclosure?.contains("1 legacy photo") == true)
        XCTAssertTrue(disclosure?.contains("encrypted bytes and archive digests") == true)
        XCTAssertTrue(
            disclosure?.contains(
                "full item opening and validation were not performed"
            ) == true
        )
        XCTAssertFalse(detail.localizedCaseInsensitiveContains("fully verified"))
    }

    func testMultipleLegacyOversizedPhotosUseHonestPluralStatus() {
        let report = makeReport(legacyOversizedPhotoCount: 3)
        let disclosure = BackupVerificationPresentationPolicy
            .legacyLimitationDisclosure(for: report)

        XCTAssertEqual(
            report.status,
            .verifiedWithLegacyLimitations(oversizedPhotoCount: 3)
        )
        XCTAssertTrue(disclosure?.contains("3 legacy photos") == true)
    }

    func testCurrentArchiveHasNoLegacyLimitationDisclosure() {
        XCTAssertNil(
            BackupVerificationPresentationPolicy.legacyLimitationDisclosure(
                for: makeReport()
            )
        )
    }

    func testFolderCompatibilityDisclosureStatesCurrentArchiveLimitation() {
        let disclosure = BackupVerificationPresentationPolicy
            .compatibilityDisclosure(for: makeReport())

        XCTAssertTrue(disclosure.contains("photos and general files"))
        XCTAssertTrue(disclosure.contains("not preserved"))
        XCTAssertTrue(disclosure.contains("folder membership"))
    }

    func testLegacyV1CompatibilityDoesNotClaimGeneralFilePreservation() {
        let disclosure = BackupVerificationPresentationPolicy
            .compatibilityDisclosure(for: makeReport(catalogVersion: 1))

        XCTAssertTrue(disclosure.contains("preserves photos only"))
        XCTAssertFalse(disclosure.contains("photos and general files"))
    }

    func testCountsDescribeContentsAndAuthenticatedEntriesSeparately() {
        let report = makeReport(
            photoCount: 1,
            generalFileCount: 1,
            authenticatedEntryCount: 1
        )

        XCTAssertEqual(
            BackupVerificationPresentationPolicy.photoCountDescription(for: report),
            "1 photo"
        )
        XCTAssertEqual(
            BackupVerificationPresentationPolicy.generalFileCountDescription(for: report),
            "1 general file"
        )
        XCTAssertEqual(
            BackupVerificationPresentationPolicy
                .authenticatedEntryCountDescription(for: report),
            "1 authenticated archive entry"
        )
    }

    func testArchiveByteFormattingDoesNotOverflowForPrimitiveValueBoundary() {
        let formatted = BackupVerificationPresentationPolicy
            .formattedArchiveByteCount(UInt64.max)

        XCTAssertEqual(formatted, "18446744073709551615 bytes")
    }

    @MainActor
    func testPublicReportViewAcceptsSanitizedReportValue() {
        _ = BackupVerificationReportView(report: makeReport())
    }

    private func makeReport(
        catalogVersion: Int = 3,
        photoCount: Int = 7,
        generalFileCount: Int = 2,
        authenticatedEntryCount: Int = 18,
        legacyOversizedPhotoCount: Int = 0
    ) -> BackupVerificationReport {
        BackupVerificationReport(
            displayName: "Family Backup.khvault",
            archiveByteCount: 12_345,
            sourceVaultCreatedAt: Date(timeIntervalSinceReferenceDate: 100),
            verifiedAt: Date(timeIntervalSinceReferenceDate: 200),
            catalogVersion: catalogVersion,
            photoCount: photoCount,
            generalFileCount: generalFileCount,
            authenticatedEntryCount: authenticatedEntryCount,
            legacyOversizedPhotoCount: legacyOversizedPhotoCount
        )
    }
}
