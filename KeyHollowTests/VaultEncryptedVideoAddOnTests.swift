import AVFoundation
import Foundation
import UIKit
import XCTest
@testable import KeyHollowEncryptedVideoAddOn

final class VaultEncryptedVideoAddOnTests: XCTestCase {
    func testOnlyExactDeclaredMOVMP4AndM4VTypesUseVideoRoute() {
        let supportedIdentifiers = [
            "com.apple.quicktime-movie",
            "public.mpeg-4",
            "com.apple.m4v-video"
        ]

        for identifier in supportedIdentifiers {
            let descriptor = VaultEncryptedVideoDescriptor(
                displayName: "misleading.bin",
                contentTypeIdentifier: identifier,
                originalByteCount: 1
            )

            XCTAssertEqual(
                VaultEncryptedVideoPolicy.kind(for: descriptor),
                .video,
                "Expected \(identifier) to be supported"
            )
        }
    }

    func testBroaderMovieDeclarationIsNotAccepted() {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "clip.mp4",
            contentTypeIdentifier: "public.movie",
            originalByteCount: 1
        )

        XCTAssertEqual(VaultEncryptedVideoPolicy.kind(for: descriptor), .unsupported)
    }

    func testAnyNonNilUnsupportedDeclarationIsAuthoritative() {
        let declaredIdentifiers = [
            "",
            "not a valid uniform type",
            "com.example.unknown-video",
            "com.adobe.pdf"
        ]

        for identifier in declaredIdentifiers {
            let descriptor = VaultEncryptedVideoDescriptor(
                displayName: "misleading.MP4",
                contentTypeIdentifier: identifier,
                originalByteCount: 1
            )

            XCTAssertEqual(
                VaultEncryptedVideoPolicy.kind(for: descriptor),
                .unsupported,
                "A non-nil declaration must prevent filename fallback"
            )
        }
    }

    func testSafeExtensionFallbackIsCaseInsensitiveOnlyWhenMetadataIsMissing() {
        for displayName in ["Evidence.MOV", "Evidence.Mp4", "Evidence.m4V"] {
            let descriptor = VaultEncryptedVideoDescriptor(
                displayName: displayName,
                contentTypeIdentifier: nil,
                originalByteCount: 1
            )

            XCTAssertEqual(
                VaultEncryptedVideoPolicy.kind(for: descriptor),
                .video,
                "Expected \(displayName) to use the safe fallback"
            )
        }
    }

    func testUnsupportedExtensionDoesNotEnterVideoRoute() {
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "notes.avi",
            contentTypeIdentifier: nil,
            originalByteCount: 1
        )

        XCTAssertEqual(VaultEncryptedVideoPolicy.kind(for: descriptor), .unsupported)
    }

    func testPlaybackSizeBoundaryIsOneThroughOneHundredMiB() {
        XCTAssertEqual(
            VaultEncryptedVideoPolicy.maximumPlaybackByteCount,
            100 * 1_024 * 1_024
        )
        XCTAssertFalse(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(0))
        XCTAssertTrue(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(1))
        XCTAssertTrue(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(
            VaultEncryptedVideoPolicy.maximumPlaybackByteCount
        ))
        XCTAssertFalse(VaultEncryptedVideoPolicy.allowsPlaybackByteCount(
            VaultEncryptedVideoPolicy.maximumPlaybackByteCount + 1
        ))
    }

    func testOutOfRangeSizePreventsOtherwiseSupportedVideoRoute() {
        for byteCount in [
            UInt64(0),
            VaultEncryptedVideoPolicy.maximumPlaybackByteCount + 1
        ] {
            let descriptor = VaultEncryptedVideoDescriptor(
                displayName: "clip.mp4",
                contentTypeIdentifier: "public.mpeg-4",
                originalByteCount: byteCount
            )

            XCTAssertEqual(
                VaultEncryptedVideoPolicy.kind(for: descriptor),
                .unsupported
            )
        }
    }

    func testPreparedPlaybackAcceptsExistingReadableRegularLocalFile() throws {
        let fileURL = try makeTemporaryFile(contents: Data([0x00, 0x01]))
        defer { removeItemIfPresent(at: fileURL) }
        let descriptor = supportedDescriptor(byteCount: 2)
        let id = UUID()

        let playback = try VaultPreparedVideoPlayback(
            id: id,
            descriptor: descriptor,
            fileURL: fileURL
        )

        XCTAssertEqual(playback.id, id)
        XCTAssertEqual(playback.descriptor, descriptor)
        XCTAssertEqual(playback.fileURL, fileURL)
    }

    func testPreparedPlaybackRejectsNonFileURL() throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/clip.mp4"))

        XCTAssertThrowsError(
            try VaultPreparedVideoPlayback(
                id: UUID(),
                descriptor: supportedDescriptor(),
                fileURL: remoteURL
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .invalidPlaybackURL
            )
        }
    }

    func testPreparedPlaybackRejectsMissingLocalFile() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingVideo-\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        XCTAssertThrowsError(
            try VaultPreparedVideoPlayback(
                id: UUID(),
                descriptor: supportedDescriptor(),
                fileURL: missingURL
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .missingPlaybackFile
            )
        }
    }

    func testPreparedPlaybackRejectsDirectory() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoDirectory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        defer { removeItemIfPresent(at: directoryURL) }

        XCTAssertThrowsError(
            try VaultPreparedVideoPlayback(
                id: UUID(),
                descriptor: supportedDescriptor(),
                fileURL: directoryURL
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .playbackURLIsDirectory
            )
        }
    }

    func testPreparedPlaybackRejectsUnsupportedDescriptor() throws {
        let fileURL = try makeTemporaryFile(contents: Data([0x00]))
        defer { removeItemIfPresent(at: fileURL) }
        let descriptor = VaultEncryptedVideoDescriptor(
            displayName: "notes.txt",
            contentTypeIdentifier: "public.plain-text",
            originalByteCount: 1
        )

        XCTAssertThrowsError(
            try VaultPreparedVideoPlayback(
                id: UUID(),
                descriptor: descriptor,
                fileURL: fileURL
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .unsupportedVideo
            )
        }
    }

    func testPlayableValidationRejectsMalformedLocalMedia() async throws {
        let fileURL = try makeTemporaryFile(
            contents: Data("not a movie container".utf8)
        )
        defer { removeItemIfPresent(at: fileURL) }
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: supportedDescriptor(),
            fileURL: fileURL
        )

        do {
            try await playback.validatePlayable()
            XCTFail("Expected malformed media validation to fail")
        } catch {
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .unplayableVideo
            )
        }
    }

    func testPlayableValidationRechecksFileExistence() async throws {
        let fileURL = try makeTemporaryFile(contents: Data([0x00]))
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: supportedDescriptor(),
            fileURL: fileURL
        )
        try FileManager.default.removeItem(at: fileURL)

        do {
            try await playback.validatePlayable()
            XCTFail("Expected a removed plaintext file to fail validation")
        } catch {
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .missingPlaybackFile
            )
        }
    }

    func testPreparedPlaybackAlwaysBuildsFullyRestrictedAsset() throws {
        let fileURL = try makeTemporaryFile(contents: Data([0x00]))
        defer { removeItemIfPresent(at: fileURL) }
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: supportedDescriptor(),
            fileURL: fileURL
        )

        let asset = playback.makeRestrictedAsset()

        XCTAssertEqual(
            asset.referenceRestrictions,
            AVAssetReferenceRestrictions.forbidAll
        )
        XCTAssertEqual(asset.url, fileURL)
    }

    func testValidLocalMovieValidatesAndRendersBoundedThumbnail() async throws {
        let fileURL = try await makeTemporaryMovie()
        defer { removeItemIfPresent(at: fileURL) }
        let byteCount = UInt64(try Data(contentsOf: fileURL).count)
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: VaultEncryptedVideoDescriptor(
                displayName: "fixture.mov",
                contentTypeIdentifier: "com.apple.quicktime-movie",
                originalByteCount: byteCount
            ),
            fileURL: fileURL
        )

        try await playback.validatePlayable()
        let thumbnail = try await VaultEncryptedVideoThumbnailRenderer.render(
            playback
        )

        XCTAssertGreaterThan(thumbnail.jpegData.count, 2)
        XCTAssertEqual(thumbnail.jpegData.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertGreaterThan(thumbnail.pixelWidth, 0)
        XCTAssertGreaterThan(thumbnail.pixelHeight, 0)
        XCTAssertLessThanOrEqual(
            thumbnail.pixelWidth,
            VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension
        )
        XCTAssertLessThanOrEqual(
            thumbnail.pixelHeight,
            VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension
        )
        XCTAssertLessThanOrEqual(
            thumbnail.jpegData.count,
            VaultEncryptedVideoThumbnailRenderer.maximumEncodedByteCount
        )
    }

    func testThumbnailGeneratorUsesTransformAndPixelBound() throws {
        let fileURL = try makeTemporaryFile(contents: Data([0x00]))
        defer { removeItemIfPresent(at: fileURL) }
        let generator = VaultEncryptedVideoThumbnailRenderer.makeImageGenerator(
            for: AVURLAsset(url: fileURL)
        )

        XCTAssertTrue(generator.appliesPreferredTrackTransform)
        XCTAssertEqual(
            generator.maximumSize,
            CGSize(
                width: VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension,
                height: VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension
            )
        )
    }

    func testThumbnailEncodingProducesBoundedJPEG() throws {
        let image = try makeTestImage(width: 32, height: 20)

        let thumbnail = try VaultEncryptedVideoThumbnailRenderer.encodedThumbnail(
            from: image
        )

        XCTAssertEqual(thumbnail.pixelWidth, 32)
        XCTAssertEqual(thumbnail.pixelHeight, 20)
        XCTAssertEqual(thumbnail.jpegData.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertLessThanOrEqual(
            thumbnail.jpegData.count,
            VaultEncryptedVideoThumbnailRenderer.maximumEncodedByteCount
        )
    }

    func testThumbnailEnvelopeRejectsInvalidDimensionsAndOversizedData() {
        XCTAssertThrowsError(
            try VaultEncryptedVideoThumbnail(
                jpegData: Data([0xFF, 0xD8]),
                pixelWidth: 0,
                pixelHeight: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultEncryptedVideoThumbnailError,
                .invalidDimensions
            )
        }

        XCTAssertThrowsError(
            try VaultEncryptedVideoThumbnail(
                jpegData: Data(
                    repeating: 0,
                    count: VaultEncryptedVideoThumbnailRenderer
                        .maximumEncodedByteCount + 1
                ),
                pixelWidth: 1,
                pixelHeight: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? VaultEncryptedVideoThumbnailError,
                .encodedThumbnailTooLarge
            )
        }
    }

    func testOversizedDecodedThumbnailIsRejected() throws {
        let image = try makeTestImage(
            width: VaultEncryptedVideoThumbnailRenderer.maximumPixelDimension + 1,
            height: 8
        )

        XCTAssertThrowsError(
            try VaultEncryptedVideoThumbnailRenderer.encodedThumbnail(from: image)
        ) { error in
            XCTAssertEqual(
                error as? VaultEncryptedVideoThumbnailError,
                .dimensionsTooLarge
            )
        }
    }

    func testRemovedLocalVideoFailsThumbnailRendering() async throws {
        let fileURL = try makeTemporaryFile(contents: Data([0x00]))
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: supportedDescriptor(),
            fileURL: fileURL
        )
        try FileManager.default.removeItem(at: fileURL)

        do {
            _ = try await VaultEncryptedVideoThumbnailRenderer.render(playback)
            XCTFail("Expected a removed local video to fail thumbnail rendering")
        } catch {
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .missingPlaybackFile
            )
        }
    }

    func testMalformedLocalVideoFailsThumbnailRendering() async throws {
        let fileURL = try makeTemporaryFile(contents: Data("malformed".utf8))
        defer { removeItemIfPresent(at: fileURL) }
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: supportedDescriptor(),
            fileURL: fileURL
        )

        do {
            _ = try await VaultEncryptedVideoThumbnailRenderer.render(playback)
            XCTFail("Expected malformed media to fail thumbnail rendering")
        } catch {
            XCTAssertEqual(
                error as? VaultPreparedVideoPlaybackError,
                .unplayableVideo
            )
        }
    }

    func testThumbnailRenderingPropagatesCancellation() async throws {
        let fileURL = try makeTemporaryFile(contents: Data("malformed".utf8))
        defer { removeItemIfPresent(at: fileURL) }
        let playback = try VaultPreparedVideoPlayback(
            id: UUID(),
            descriptor: supportedDescriptor(),
            fileURL: fileURL
        )

        let task = Task<VaultEncryptedVideoThumbnail, Error> {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await VaultEncryptedVideoThumbnailRenderer.render(playback)
        }

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to propagate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    @MainActor
    func testPlayerLifecycleReleasePausesAndClearsCurrentItem() throws {
        let fileURL = try makeTemporaryFile(contents: Data([0x00]))
        defer { removeItemIfPresent(at: fileURL) }
        let player = AVPlayer(playerItem: AVPlayerItem(url: fileURL))
        player.play()

        VaultEncryptedVideoPlayerLifecycle.release(player)

        XCTAssertEqual(player.rate, 0)
        XCTAssertNil(player.currentItem)

        // Repeated teardown is deliberately harmless.
        VaultEncryptedVideoPlayerLifecycle.release(player)
        XCTAssertNil(player.currentItem)
    }

    func testPlayerFailurePolicyRecognizesOnlyFailedStatus() {
        XCTAssertFalse(
            VaultEncryptedVideoPlayerFailurePolicy.indicatesFailure(.unknown)
        )
        XCTAssertFalse(
            VaultEncryptedVideoPlayerFailurePolicy.indicatesFailure(.readyToPlay)
        )
        XCTAssertTrue(
            VaultEncryptedVideoPlayerFailurePolicy.indicatesFailure(.failed)
        )
    }

    private func supportedDescriptor(
        byteCount: UInt64 = 1
    ) -> VaultEncryptedVideoDescriptor {
        VaultEncryptedVideoDescriptor(
            displayName: "clip.mp4",
            contentTypeIdentifier: "public.mpeg-4",
            originalByteCount: byteCount
        )
    }

    private func makeTemporaryFile(contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptedVideo-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try contents.write(to: url, options: .atomic)
        return url
    }

    private func makeTemporaryMovie() async throws -> URL {
        let width = 32
        let height = 32
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptedVideo-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        var didFinish = false
        defer {
            if !didFinish {
                removeItemIfPresent(at: url)
            }
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(input) else {
            throw TinyMovieFixtureError.cannotAddVideoInput
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? TinyMovieFixtureError.cannotStartWriting
        }
        writer.startSession(atSourceTime: .zero)

        do {
            let pixelBuffer = try makePixelBuffer(width: width, height: height)
            try await waitUntilReady(input, writer: writer)
            guard adaptor.append(pixelBuffer, withPresentationTime: .zero) else {
                throw writer.error ?? TinyMovieFixtureError.cannotAppendFrame
            }

            writer.endSession(atSourceTime: CMTime(value: 1, timescale: 30))
            input.markAsFinished()
            try await finishWriting(writer)
        } catch {
            writer.cancelWriting()
            throw error
        }
        guard writer.status == .completed else {
            throw writer.error ?? TinyMovieFixtureError.cannotFinishWriting
        }
        didFinish = true
        return url
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
            throw TinyMovieFixtureError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw TinyMovieFixtureError.cannotCreatePixelBuffer
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for rowIndex in 0..<height {
            let row = baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for columnIndex in 0..<width {
                let pixelOffset = columnIndex * 4
                row[pixelOffset] = 0xD0
                row[pixelOffset + 1] = 0x60
                row[pixelOffset + 2] = 0x20
                row[pixelOffset + 3] = 0xFF
            }
        }
        return pixelBuffer
    }

    private func waitUntilReady(
        _ input: AVAssetWriterInput,
        writer: AVAssetWriter
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))

        while clock.now < deadline {
            try Task.checkCancellation()
            if input.isReadyForMoreMediaData {
                return
            }

            switch writer.status {
            case .failed:
                throw writer.error ?? TinyMovieFixtureError.cannotAppendFrame
            case .cancelled:
                throw TinyMovieFixtureError.writerCancelled
            default:
                break
            }

            try await clock.sleep(for: .milliseconds(10))
        }

        throw TinyMovieFixtureError.inputReadinessTimedOut
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        let gate = TinyMovieFinishGate(writer: writer)
        try await gate.wait(timeout: .seconds(10))
    }

    private func removeItemIfPresent(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private enum TinyMovieFixtureError: Error {
        case cannotAddVideoInput
        case cannotStartWriting
        case cannotAppendFrame
        case cannotFinishWriting
        case cannotCreatePixelBuffer
        case inputReadinessTimedOut
        case finishTimedOut
        case writerCancelled
    }

    private final class TinyMovieFinishGate: @unchecked Sendable {
        private let writer: AVAssetWriter
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var result: Result<Void, Error>?
        private var finishTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?

        init(writer: AVAssetWriter) {
            self.writer = writer
        }

        func wait(timeout: Duration) async throws {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if let result = register(continuation) {
                        continuation.resume(with: result)
                    } else {
                        beginWritingFinish(timeout: timeout)
                    }
                }
            } onCancel: {
                cancel()
            }
        }

        private func register(
            _ continuation: CheckedContinuation<Void, Error>
        ) -> Result<Void, Error>? {
            lock.lock()
            defer { lock.unlock() }

            if let result {
                return result
            }
            self.continuation = continuation
            return nil
        }

        private func beginWritingFinish(timeout: Duration) {
            let finishTask = Task { [self] in
                await writer.finishWriting()
                let result: Result<Void, Error>
                switch writer.status {
                case .completed:
                    result = .success(())
                case .cancelled:
                    result = .failure(TinyMovieFixtureError.writerCancelled)
                default:
                    result = .failure(
                        writer.error ?? TinyMovieFixtureError.cannotFinishWriting
                    )
                }
                resolve(result)
            }
            let timeoutTask = Task { [self] in
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }

                if resolve(.failure(TinyMovieFixtureError.finishTimedOut)) {
                    writer.cancelWriting()
                }
            }

            lock.lock()
            if result == nil {
                self.finishTask = finishTask
                self.timeoutTask = timeoutTask
                lock.unlock()
            } else {
                lock.unlock()
                finishTask.cancel()
                timeoutTask.cancel()
            }
        }

        @discardableResult
        private func resolve(_ result: Result<Void, Error>) -> Bool {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return false
            }

            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            let finishTask = self.finishTask
            self.finishTask = nil
            let timeoutTask = self.timeoutTask
            self.timeoutTask = nil
            lock.unlock()

            finishTask?.cancel()
            timeoutTask?.cancel()
            continuation?.resume(with: result)
            return true
        }

        private func cancel() {
            if resolve(.failure(CancellationError())) {
                writer.cancelWriting()
            }
        }
    }
}
