import XCTest
import KeyHollowCatalogSearchAddOn

final class VaultCatalogSearchAddOnTests: XCTestCase {
    func testEmptyAndWhitespaceOnlyQueriesMatchEveryCandidate() {
        XCTAssertTrue(VaultCatalogSearchQuery("").matches("IMG_4130"))
        XCTAssertTrue(VaultCatalogSearchQuery("  \n\t ").matches("Documents"))
    }

    func testMatchingIsCaseDiacriticAndWidthInsensitive() {
        XCTAssertTrue(VaultCatalogSearchQuery("resume").matches("Résumé.pdf"))
        XCTAssertTrue(VaultCatalogSearchQuery("ｋｅｙ").matches("KEY Hollow"))
    }

    func testEveryTermMustMatchInAnyOrder() {
        let query = VaultCatalogSearchQuery("2026 family")

        XCTAssertTrue(query.matches("Family Photos 2026"))
        XCTAssertFalse(query.matches("Family Photos 2025"))
        XCTAssertFalse(query.matches("Receipts 2026"))
    }

    func testQueryAndCandidateWorkAreBounded() {
        let query = VaultCatalogSearchQuery(String(repeating: "a", count: 400))

        XCTAssertEqual(
            query.rawValue.count,
            VaultCatalogSearchQuery.maximumQueryCharacterCount
        )
        XCTAssertFalse(
            VaultCatalogSearchQuery("needle").matches(
                String(repeating: "a", count: 2_000) + " needle"
            )
        )
    }
}
