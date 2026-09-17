import AVFoundation
import AVKit
import Combine
import Foundation
import SwiftUI
import UIKit

/// Kept separate from presentation state so terminal teardown remains directly
/// verifiable and idempotent on every dismissal path.
@MainActor
enum VaultEncryptedVideoPlayerLifecycle {
    static func release(_ player: AVPlayer?) {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }
}

enum VaultEncryptedVideoPlayerFailurePolicy {
    static func indicatesFailure(_ status: AVPlayerItem.Status) -> Bool {
        status == .failed
    }
}

/// Keeps protected playback on the device and inside KeyHollow's lifecycle.
/// The settings live in one testable policy instead of depending on AVKit's
/// permissive defaults.
@MainActor
enum VaultEncryptedVideoPlayerSecurityPolicy {
    static func configure(_ player: AVPlayer) {
        player.allowsExternalPlayback = false
        player.usesExternalPlaybackWhileExternalScreenIsActive = false
    }

    static func configure(_ controller: AVPlayerViewController) {
        controller.allowsPictureInPicturePlayback = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.updatesNowPlayingInfoCenter = false
        controller.allowsVideoFrameAnalysis = false
    }
}

/// AVPlayerItem is intentionally contained in this narrowly scoped monitor.
/// AVFoundation owns its synchronization; callers receive only a Sendable
/// Boolean result. This lets strict-concurrency tasks race the two independent
/// failure channels without moving application state between executors.
@MainActor
final class VaultEncryptedVideoPlayerFailureMonitor: @unchecked Sendable {
    typealias StatusProvider = () -> AVPlayerItem.Status
    typealias PlaybackEndFailureWaiter = () async -> Bool

    private let statusProvider: StatusProvider
    private let playbackEndFailureWaiter: PlaybackEndFailureWaiter

    init(item: AVPlayerItem) {
        statusProvider = { item.status }
        playbackEndFailureWaiter = {
            let failures = NotificationCenter.default.notifications(
                named: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: item
            ).map { _ in () }

            for await _ in failures {
                return !Task.isCancelled
            }
            return false
        }
    }

    init(
        statusProvider: @escaping StatusProvider,
        playbackEndFailureWaiter: @escaping PlaybackEndFailureWaiter
    ) {
        self.statusProvider = statusProvider
        self.playbackEndFailureWaiter = playbackEndFailureWaiter
    }

    func waitForFailure() async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { [self] in
                await waitForFailedStatus()
            }
            group.addTask { [self] in
                await waitForPlaybackEndFailure()
            }

            while let didFail = await group.next() {
                if didFail {
                    group.cancelAll()
                    return true
                }
            }
            return false
        }
    }

    private func waitForFailedStatus() async -> Bool {
        while !Task.isCancelled {
            if VaultEncryptedVideoPlayerFailurePolicy.indicatesFailure(
                statusProvider()
            ) {
                return true
            }

            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return false
    }

    private func waitForPlaybackEndFailure() async -> Bool {
        await playbackEndFailureWaiter()
    }
}

@MainActor
final class VaultEncryptedVideoPresentationAnchorViewController:
    UIViewController
{
    weak var session: VaultEncryptedVideoPlaybackSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session?.presentationAnchorDidAppear(self)
    }

    /// A modal AVPlayerViewController may temporarily remove this anchor's
    /// view from the hierarchy. Its module-owned session remains the authority
    /// for playback and terminal release.
    func prepareForRepresentableDismantle() {
        session?.presentationAnchorDidDismantle(self)
        session = nil
    }
}

enum VaultEncryptedVideoSessionTeardownEvent: Equatable {
    case rejectedNewPresentations
    case playerPaused
    case monitorFinished
    case modalDismissed
    case playerDetached
    case leaseReleased
}

/// Owns every UIKit and AVFoundation object for one active playback lease.
/// SwiftUI view and representable lifetimes are intentionally not ownership
/// boundaries: a full-screen UIKit presentation can remove those views while
/// the same playback session remains valid.
@MainActor
public final class VaultEncryptedVideoPlaybackSession:
    NSObject,
    ObservableObject,
    @MainActor AVPlayerViewControllerDelegate,
    @MainActor UIAdaptivePresentationControllerDelegate
{
    typealias FailureWaiter = @MainActor (AVPlayerItem) async -> Bool
    typealias TeardownObserver = @MainActor (
        VaultEncryptedVideoSessionTeardownEvent
    ) -> Void

    private enum Phase: Equatable {
        case idle
        case ready
        case stopping
    }

    @Published public private(set) var activePlaybackID: UUID?
    @Published public private(set) var canPresent = false
    @Published public private(set) var isPlayerPresented = false

    private let playerController: AVPlayerViewController
    private let waitForFailure: FailureWaiter
    private let teardownObserver: TeardownObserver?

    private var phase: Phase = .idle
    private var item: AVPlayerItem?
    private var player: AVPlayer?
    private var monitorTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var releasePlayerLease: (() -> Void)?
    private var reportFailure: ((VaultPreparedVideoPlaybackError) -> Void)?
    private var didReleasePlayerLease = false
    private var hasPendingPresentation = false
    private var isAnchorReadyForPresentation = false
    private var isPresentationTransitionActive = false
    private var transitionWaiters: [CheckedContinuation<Void, Never>] = []
    private weak var anchorController:
        VaultEncryptedVideoPresentationAnchorViewController?

    public override init() {
        playerController = AVPlayerViewController()
        waitForFailure = { item in
            await VaultEncryptedVideoPlayerFailureMonitor(item: item).waitForFailure()
        }
        teardownObserver = nil
        super.init()
        finishInitialization()
    }

    init(
        waitForFailure: @escaping FailureWaiter,
        teardownObserver: TeardownObserver? = nil
    ) {
        playerController = AVPlayerViewController()
        self.waitForFailure = waitForFailure
        self.teardownObserver = teardownObserver
        super.init()
        finishInitialization()
    }

    private func finishInitialization() {
        playerController.view.backgroundColor = .black
        playerController.videoGravity = .resizeAspect
        playerController.modalPresentationStyle = .fullScreen
        playerController.delegate = self
        VaultEncryptedVideoPlayerSecurityPolicy.configure(playerController)
    }

    /// Installs one validated protected playback and acquires its application
    /// lease exactly once. Recomposition with the same playback is a no-op.
    @discardableResult
    public func activate(
        playback: VaultPreparedVideoPlayback,
        onPlayerWillAttach: () -> Bool = { true },
        onPlayerReleased: @escaping () -> Void = {},
        onFailure: ((VaultPreparedVideoPlaybackError) -> Void)? = nil
    ) -> Bool {
        if activePlaybackID == playback.id {
            return phase == .ready
        }
        guard phase == .idle, teardownTask == nil else { return false }
        guard onPlayerWillAttach() else { return false }

        let item = AVPlayerItem(asset: playback.makeRestrictedAsset())
        let player = AVPlayer(playerItem: item)
        VaultEncryptedVideoPlayerSecurityPolicy.configure(player)
        VaultEncryptedVideoPlayerSecurityPolicy.configure(playerController)

        self.item = item
        self.player = player
        playerController.player = player
        releasePlayerLease = onPlayerReleased
        reportFailure = onFailure
        didReleasePlayerLease = false
        activePlaybackID = playback.id
        phase = .ready
        canPresent = true

        startFailureMonitor(item: item, playbackID: playback.id)

        // Each newly activated playback opens once. Returning from AVKit's Done
        // control leaves the outer pager on a poster with an explicit replay
        // button instead of immediately opening the modal again.
        hasPendingPresentation = true
        attemptPendingPresentation()
        return true
    }

    /// Explicit replay after the user returns from AVKit to the selected page.
    public func requestPresentation() {
        guard phase == .ready,
              canPresent,
              !isPlayerPresented,
              !isPresentationTransitionActive else { return }
        hasPendingPresentation = true
        attemptPendingPresentation()
    }

    /// Synchronous terminal signal for selection changes, the outer viewer's
    /// Done action, lock, and backgrounding. AVKit's own Done action is not
    /// terminal: it returns to the poster for explicit replay. A terminal stop
    /// immediately rejects new presentations and pauses; the retained teardown
    /// task completes the ordered asynchronous release.
    public func requestStop() {
        guard phase != .idle else { return }
        guard phase != .stopping else { return }

        phase = .stopping
        canPresent = false
        hasPendingPresentation = false
        teardownObserver?(.rejectedNewPresentations)

        player?.pause()
        teardownObserver?(.playerPaused)

        let endingMonitor = monitorTask
        monitorTask = nil
        endingMonitor?.cancel()

        teardownTask = Task { @MainActor [self] in
            if let endingMonitor {
                await endingMonitor.value
            }
            teardownObserver?(.monitorFinished)

            await waitForPresentationTransition()
            await dismissPlayerControllerIfNeeded()
            teardownObserver?(.modalDismissed)

            playerController.player = nil
            VaultEncryptedVideoPlayerLifecycle.release(player)
            item = nil
            player = nil
            isPlayerPresented = false
            teardownObserver?(.playerDetached)

            releaseLeaseOnce()

            reportFailure = nil
            activePlaybackID = nil
            phase = .idle
            teardownTask = nil
        }
    }

    public func stopAndWait() async {
        requestStop()
        let endingTask = teardownTask
        await endingTask?.value
    }

    private func startFailureMonitor(item: AVPlayerItem, playbackID: UUID) {
        monitorTask = Task { @MainActor [self] in
            let didFail = await waitForFailure(item)
            guard !Task.isCancelled,
                  didFail,
                  phase == .ready,
                  activePlaybackID == playbackID else {
                return
            }

            schedulePlaybackFailure(after: playbackID)
        }
    }

    private func schedulePlaybackFailure(after playbackID: UUID) {
        guard let completedMonitor = monitorTask else { return }
        Task { @MainActor [weak self] in
            // The supervisor is a different task, so it can prove that the
            // failure monitor has actually returned before terminal teardown
            // cancels and awaits that same retained handle.
            await completedMonitor.value
            guard let self,
                  self.phase == .ready,
                  self.activePlaybackID == playbackID else { return }
            let failureHandler = self.reportFailure
            self.requestStop()
            failureHandler?(.unplayableVideo)
        }
    }

    private func attemptPendingPresentation() {
        guard let anchorController,
              hasPendingPresentation,
              phase == .ready,
              canPresent,
              isAnchorReadyForPresentation,
              !isPlayerPresented,
              !isPresentationTransitionActive,
              anchorController.viewIfLoaded?.window != nil,
              anchorController.presentedViewController == nil else {
            return
        }

        hasPendingPresentation = false
        beginPresentationTransition()
        anchorController.present(playerController, animated: true) { [weak self] in
            guard let self else { return }
            let didPresent = self.playerController.presentingViewController != nil
            self.isPlayerPresented = didPresent
            if didPresent {
                self.playerController.presentationController?.delegate = self
            } else if self.phase == .ready, self.canPresent {
                // Keep one retry available on the visible poster if UIKit
                // declines a presentation instead of losing the request.
                self.hasPendingPresentation = true
            }
            self.finishPresentationTransition()
        }
    }

    private func dismissPlayerControllerIfNeeded() async {
        await waitForPresentationTransition()
        guard playerController.presentingViewController != nil || isPlayerPresented else {
            finishModalDismissal()
            return
        }

        beginPresentationTransition()
        await withCheckedContinuation { continuation in
            playerController.dismiss(animated: false) { [weak self] in
                self?.finishModalDismissal()
                continuation.resume()
            }
        }
        finishPresentationTransition()
    }

    func finishModalDismissal() {
        hasPendingPresentation = false
        player?.pause()
        isPlayerPresented = false
    }

    private func beginPresentationTransition() {
        isPresentationTransitionActive = true
    }

    private func finishPresentationTransition() {
        guard isPresentationTransitionActive else { return }
        isPresentationTransitionActive = false
        let waiters = transitionWaiters
        transitionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForPresentationTransition() async {
        guard isPresentationTransitionActive else { return }
        await withCheckedContinuation { continuation in
            transitionWaiters.append(continuation)
        }
    }

    private func releaseLeaseOnce() {
        guard !didReleasePlayerLease else { return }
        didReleasePlayerLease = true
        let release = releasePlayerLease
        releasePlayerLease = nil
        release?()
        teardownObserver?(.leaseReleased)
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator:
            any UIViewControllerTransitionCoordinator
    ) {
        beginModalDismissal()
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self else { return }
            if !context.isCancelled {
                self.finishModalDismissal()
            }
            self.finishPresentationTransition()
        }
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForFullScreenExitWithCompletionHandler completionHandler:
            @escaping @Sendable (Bool) -> Void
    ) {
        // The root presentation anchor remains on the selected media page.
        completionHandler(true)
    }

    public func playerViewControllerWillBeginDismissalTransition(
        _ playerViewController: AVPlayerViewController
    ) {
        beginModalDismissal()
    }

    public func playerViewControllerDidEndDismissalTransition(
        _ playerViewController: AVPlayerViewController
    ) {
        if playerController.presentingViewController == nil {
            finishModalDismissal()
        }
        finishPresentationTransition()
    }

    public func presentationControllerWillDismiss(
        _ presentationController: UIPresentationController
    ) {
        beginModalDismissal()
    }

    public func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        finishModalDismissal()
        finishPresentationTransition()
    }

    func presentationAnchorDidAppear(
        _ controller: VaultEncryptedVideoPresentationAnchorViewController
    ) {
        attachPresentationAnchor(controller)
        isAnchorReadyForPresentation = true
        // UIKit can restore the presenter without sending every adaptive-
        // presentation callback (for example AVKit's own Done route). The
        // stable root anchor is the final source of truth that the modal is no
        // longer attached, so reconcile before enabling explicit replay.
        if isPlayerPresented,
           playerController.presentingViewController == nil {
            finishModalDismissal()
            finishPresentationTransition()
        }
        attemptPendingPresentation()
    }

    func presentationAnchorDidUpdate(
        _ controller: VaultEncryptedVideoPresentationAnchorViewController
    ) {
        attachPresentationAnchor(controller)
    }

    func presentationAnchorDidDismantle(
        _ controller: VaultEncryptedVideoPresentationAnchorViewController
    ) {
        guard anchorController === controller else { return }
        anchorController = nil
        isAnchorReadyForPresentation = false
    }

    private func attachPresentationAnchor(
        _ controller: VaultEncryptedVideoPresentationAnchorViewController
    ) {
        if anchorController !== controller {
            isAnchorReadyForPresentation = false
        }
        anchorController = controller
        controller.session = self
    }

    private func beginModalDismissal() {
        hasPendingPresentation = false
        beginPresentationTransition()
        player?.pause()
    }

    // Focused test accessors verify object ownership and terminal release
    // without exposing UIKit implementation details as public API.
    var retainedPlayerController: AVPlayerViewController { playerController }
    var attachedAnchorController: UIViewController? { anchorController }
    var activePlayer: AVPlayer? { player }
    var presentationIsPending: Bool { hasPendingPresentation }
    var presentationAnchorIsReady: Bool { isAnchorReadyForPresentation }
}

@MainActor
private struct VaultEncryptedVideoPresentationAnchorRepresentable:
    UIViewControllerRepresentable
{
    @ObservedObject var session: VaultEncryptedVideoPlaybackSession

    func makeUIViewController(
        context: Context
    ) -> VaultEncryptedVideoPresentationAnchorViewController {
        let controller = VaultEncryptedVideoPresentationAnchorViewController()
        session.presentationAnchorDidUpdate(controller)
        return controller
    }

    func updateUIViewController(
        _ controller: VaultEncryptedVideoPresentationAnchorViewController,
        context: Context
    ) {
        session.presentationAnchorDidUpdate(controller)
    }

    static func dismantleUIViewController(
        _ controller: VaultEncryptedVideoPresentationAnchorViewController,
        coordinator: Void
    ) {
        controller.prepareForRepresentableDismantle()
    }
}

/// Mount this once at the media viewer root. It remains independent of the
/// active pager page and gives the playback session a stable UIKit presenter.
@MainActor
public struct VaultEncryptedVideoPresentationAnchorView: View {
    @ObservedObject private var session: VaultEncryptedVideoPlaybackSession

    public init(session: VaultEncryptedVideoPlaybackSession) {
        self.session = session
    }

    public var body: some View {
        VaultEncryptedVideoPresentationAnchorRepresentable(session: session)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Poster/replay surface for one validated local video. Actual playback is
/// presented by the module-owned session from the viewer-root UIKit anchor.
@MainActor
public struct VaultEncryptedVideoPlayerView: View {
    @ObservedObject private var session: VaultEncryptedVideoPlaybackSession
    private let playback: VaultPreparedVideoPlayback
    private let onPlayerWillAttach: () -> Bool
    private let onPlayerReleased: () -> Void
    private let onFailure: ((VaultPreparedVideoPlaybackError) -> Void)?

    public init(
        session: VaultEncryptedVideoPlaybackSession,
        playback: VaultPreparedVideoPlayback,
        onPlayerWillAttach: @escaping () -> Bool = { true },
        onPlayerReleased: @escaping () -> Void = {},
        onFailure: ((VaultPreparedVideoPlaybackError) -> Void)? = nil
    ) {
        self.session = session
        self.playback = playback
        self.onPlayerWillAttach = onPlayerWillAttach
        self.onPlayerReleased = onPlayerReleased
        self.onFailure = onFailure
    }

    public var body: some View {
        ZStack {
            Color.clear

            Button {
                session.requestPresentation()
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 58))
                    Text("Play Full Screen")
                        .font(.headline)
                }
                .padding(22)
                .foregroundStyle(.white)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(
                session.activePlaybackID != playback.id
                    || !session.canPresent
                    || session.isPlayerPresented
            )
            .accessibilityLabel("Play \(playback.descriptor.displayName) full screen")
        }
        .onAppear {
            session.activate(
                playback: playback,
                onPlayerWillAttach: onPlayerWillAttach,
                onPlayerReleased: onPlayerReleased,
                onFailure: onFailure
            )
        }
    }
}
