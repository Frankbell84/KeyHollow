import SwiftUI
import KeyHollowCatalogSearchAddOn

/// Search and ordering controls bind only to their presentation values.
struct VaultGallerySearchControls: View {
    @Binding var searchText: String
    @Binding var catalogSortOrder: VaultCatalogSortOrder
    let isQueryEmpty: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search this location", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Search this vault location")

            if !isQueryEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            Menu {
                Picker("Sort", selection: $catalogSortOrder) {
                    ForEach(VaultCatalogSortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Sort vault items")
            .accessibilityValue(catalogSortOrder.title)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private extension VaultCatalogSortOrder {
    var title: String {
        switch self {
        case .vaultOrder:
            "Vault Order"
        case .newestFirst:
            "Newest First"
        case .oldestFirst:
            "Oldest First"
        case .nameAscending:
            "Name A–Z"
        case .nameDescending:
            "Name Z–A"
        }
    }
}
