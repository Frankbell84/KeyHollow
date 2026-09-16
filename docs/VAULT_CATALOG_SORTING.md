# Vault Catalog Sorting

Vault Catalog Sorting is a presentation-only refinement built on the physically
accepted Build 47 search baseline. It reorders only the already-visible root or
folder catalog and does not change encrypted storage, folder membership, media
loading, or the `.khvault` archive format.

## Boundary

The existing independently compiled `KeyHollowCatalogSearchAddOn` now owns the
closely related catalog-ordering policy. It receives only bounded sanitized
display titles, timestamps, and stable ordinals. It does not receive vault or
record identifiers, sessions, keys, protected stores, folder manifests, URLs,
ciphertext, plaintext, thumbnails, archive parsers, network clients, or
mutation closures.

The application composition layer maps the current location's immutable
presentation values into descriptors and applies returned offsets to its local
snapshot. Folders remain ahead of items as established by the gallery layout.

## Behavior

- **Vault Order** preserves the accepted baseline: root folders remain
  name-ordered and visible items remain newest-first.
- Optional choices are **Newest First**, **Oldest First**, **Name A–Z**, and
  **Name Z–A**.
- Name ordering is case-, diacritic-, and width-insensitive and number-aware.
- Name work is bounded to 1,024 characters per descriptor.
- Equal metadata uses a stable ordinal and then the original input offset, so
  recomposition cannot randomly shuffle tiles.
- Search filters first and retains the selected order. Selection, media queues,
  export, move, and deletion operate on that visible ordered snapshot.
- The sort choice is presentation state only. It never rewrites persistent
  records, folder manifests, or portable archives.

## Deliberate exclusions

This phase does not add recursive search, content indexing, OCR, document-text
search, metadata editing, favorites, albums, nested folders, cross-vault
references, accounts, networking, analytics, or archive changes. Those remain
separately reviewed work.

## Acceptance

The add-on must pass pure ordering tests, architecture and workflow gates, the
complete simulator/security/lifecycle suite, Swift CodeQL, exact-main CI,
signing-only preflight, and physical-device regression testing under
`docs/ADDON_RELEASE_POLICY.md` before distribution expands.
