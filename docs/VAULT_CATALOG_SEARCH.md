# Vault Catalog Search Add-on

Vault Catalog Search is a presentation-only refinement built on the accepted
Build 46 baseline. It filters the already visible vault catalog without
changing encrypted storage, folder membership, media loading, or the
`.khvault` archive format.

## Boundary

`KeyHollowCatalogSearchAddOn` receives only a bounded query and bounded display
text. It does not receive vault identifiers, sessions, keys, protected records,
stores, folder manifests, URLs, ciphertext, plaintext, thumbnails, archive
parsers, network clients, or mutation closures. The target is independently
compiled with strict concurrency and warnings treated as errors.

The application composition layer owns the current-location scope. It passes
only root folder names and the sanitized titles already supplied to the gallery
UI. Search never traverses into a different folder and never reads protected
storage directly.

## Behavior

- Matching is case-, diacritic-, and width-insensitive.
- Whitespace separates terms, and every term must occur in the display text.
- Query work is bounded to 256 characters and candidate work to 1,024
  characters.
- An empty query preserves the accepted deterministic gallery order.
- A nonempty query filters root folders and the current location's items.
- Opening media from search results creates a navigation queue from those
  filtered results only.
- Selection actions apply only to visible filtered items.
- Changing vaults or moving between the root and a folder clears the query.
- A zero-match query presents a dedicated `No Results` state.

## Deliberate exclusions

This phase does not add sorting, recursive search, content indexing, OCR,
document-text search, metadata editing, nested folders, cross-vault references,
accounts, networking, analytics, or archive changes. Those remain separately
reviewed add-ons.

## Acceptance

The add-on must pass its pure matching tests, architecture and workflow gates,
the complete simulator/security/lifecycle suite, Swift CodeQL, exact-main CI,
signing-only preflight, and physical-device regression testing under
`docs/ADDON_RELEASE_POLICY.md` before distribution expands.
