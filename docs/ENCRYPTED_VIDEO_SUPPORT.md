# Encrypted Video Support Boundary

Roadmap add-on #4 adds first-class playback and thumbnails for video already
stored by General File Support. It must not introduce a second encrypted store,
change `.khvault`, or weaken the 100 MB bounded-ingress contract.

## Ownership

`KeyHollowEncryptedVideoAddOn` owns:

- conservative video classification from immutable name/type/size metadata;
- a validated local-file playback handoff;
- later video thumbnail and player presentation behavior.

The add-on never receives a vault key, session capability, encrypted manifest,
general-file record, protected-store location, transfer coordinator, network
client, or remote-service SDK.

The application composition layer owns:

- choosing an authenticated general-file record;
- asking General File Support to authenticate and decrypt that record;
- the protected temporary plaintext file and its cleanup;
- revoking playback and deleting temporary plaintext on dismissal, lock,
  cancellation, backgrounding, and failure;
- storing any generated presentation thumbnail through the existing encrypted
  Folder Presentation boundary.

## Initial compatibility boundary

- Existing encrypted video files remain ordinary `VaultGeneralFileRecord`
  entries; there is no data migration.
- Existing `.khvault` archives remain byte-compatible.
- The first release recognizes QuickTime (`.mov`) and MPEG-4 (`.mp4`, `.m4v`)
  movies and retains the current 100 MB ingress ceiling.
- A recognized non-video content type overrides a misleading filename
  extension so renamed arbitrary files are not sent to a media decoder.
- Larger streaming imports require a later, separately reviewed encrypted
  storage design and are not silently added to this phase.

## Required security tests

1. Type and extension routing, including mismatches.
2. Empty and oversized input rejection.
3. Local-file-only playback handoff.
4. Temporary plaintext cleanup on success, failure, cancellation, dismissal,
   vault lock, and background transition.
5. Malformed or unplayable media failure without gallery or vault corruption.
6. Bounded thumbnail generation with encrypted-at-rest thumbnail persistence.
7. Existing photo, image-file, non-video-file, selection, folder, export, and
   `.khvault` regression coverage.
