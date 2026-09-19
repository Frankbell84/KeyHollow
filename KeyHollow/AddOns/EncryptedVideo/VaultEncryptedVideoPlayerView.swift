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

    private var playerController: AVPlayerViewController
    private let waitForFailure: FailureWaiter
    private let teardownObserver: TeardownObserver?

    private var phase: Phase = .idle
    private var item: AVPlayerItem?
    private var player: AVPlayer?
    private var monitorTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var releasePlayerLease: (() -> Void)?
    private var reportFailure: ((VaultPreparedVideoPlaybackError) -> Void)?
    private var reportUserDismissal: (() -> Void)?
    private var didReleasePlayerLease = false
    private var hasPendingPresentation = false
    private var isAnchorReadyForPresentation = false
    private var isPresentationTransitionActive = false
    private var playbackGeneration: UInt64 = 0
    private var presentationEpoch: UInt64 = 0
    private var presentationControllerEpochs: [
        ObjectIdentifier: (controller: UIPresentationController, epoch: UInt64)
    ] = [:]
    private weak var activePresentationController: UIPresentationController?
    private weak var anchorController:
        VaultEncryptedVideoPresentationAnchorViewController?

    /// UIKit can stop delivering presentation completions while the scene is
    /// backgrounding. Terminal cleanup may briefly give an in-flight
    /// transition a chance to settle, but it must never retain the protected
    /// player/file lease indefinitely waiting for an animation callback.
    private static let terminalTransitionWaitLimit: Duration = .milliseconds(250)
    private static let terminalTransitionPollInterval: Duration = .milliseconds(10)

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
        configurePlayerController(playerController)
    }

    private func configurePlayerController(_ controller: AVPlayerViewController) {
        controller.view.backgroundColor = .black
        controller.videoGravity = .resizeAspect
        // Let AVKit choose its fullscreen presentation, including its close
        // control and interactive swipe-down dismissal. Forcing UIKit's
        // generic fullScreen style bypasses that player-specific presentation.
        controller.modalPresentationStyle = .automatic
        controller.delegate = self
        VaultEncryptedVideoPlayerSecurityPolicy.configure(controller)
    }

    /// Installs one validated protected playback and acquires its application
    /// lease exactly once. Recomposition with the same playback is a no-op.
    @discardableResult
    public func activate(
        playback: VaultPreparedVideoPlayback,
        onPlayerWillAttach: () -> Bool = { true },
        onPlayerReleased: @escaping () -> Void = {},
        onFailure: ((VaultPreparedVideoPlaybackError) -> Void)? = nil,
        onDismissal: (() -> Void)? = nil
    ) -> Bool {
        if activePlaybackID == playback.id {
            return phase == .ready
        }
        guard phase == .idle, teardownTask == nil else { return false }
        guard onPlayerWillAttach() else { return false }

        playbackGeneration &+= 1
        presentationEpoch &+= 1
        presentationControllerEpochs.removeAll()
        activePresentationController = nil
        // A retired UIKit controller may report a very late transition entry.
        // Each fresh playback owns a clean local gate and a fresh controller.
        isPresentationTransitionActive = false
        isPlayerPresented = false
        let controller = AVPlayerViewController()
        configurePlayerController(controller)
        let item = AVPlayerItem(asset: playback.makeRestrictedAsset())
        let player = AVPlayer(playerItem: item)
        VaultEncryptedVideoPlayerSecurityPolicy.configure(player)

        playerController = controller
        self.item = item
        self.player = player
        controller.player = player
        releasePlayerLease = onPlayerReleased
        reportFailure = onFailure
        reportUserDismissal = onDismissal
        didReleasePlayerLease = false
        activePlaybackID = playback.id
        phase = .ready
        canPresent = true

        startFailureMonitor(item: item, playbackID: playback.id)

        // Each newly activated playback opens once. The application's dismissal
        // callback closes the outer viewer; recomposition must never reopen it.
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
        if hasPendingPresentation {
            attemptPendingPresentation()
            return
        }
        replacePlayerControllerForReplay()
        hasPendingPresentation = true
        attemptPendingPresentation()
    }

    private func replacePlayerControllerForReplay() {
        let retiredController = playerController
        retiredController.delegate = nil
        retiredController.presentationController?.delegate = nil
        retiredController.player = nil

        presentationEpoch &+= 1
        presentationControllerEpochs.removeAll()
        activePresentationController = nil
        let replacementController = AVPlayerViewController()
        configurePlayerController(replacementController)
        replacementController.player = player
        playerController = replacementController
    }

    /// Synchronous terminal signal for selection changes, the outer viewer's
    /// Done action, lock, and backgrounding. AVKit's completed user dismissal
    /// notifies the owner, which requests the same terminal cleanup. A stop
    /// immediately rejects new presentations and pauses; the retained teardown
    /// task completes the ordered asynchronous release.
    public func requestStop() {
        guard phase != .idle else { return }
        guard phase != .stopping else { return }

        playbackGeneration &+= 1
        let teardownGeneration = playbackGeneration
        let retiringPlayerController = playerController
        phase = .stopping
        reportUserDismissal = nil
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
            await dismissPlayerControllerIfNeeded(
                retiringPlayerController,
                generation: teardownGeneration
            )
            teardownObserver?(.modalDismissed)

            retiringPlayerController.player = nil
            VaultEncryptedVideoPlayerLifecycle.release(player)
            item = nil
            player = nil
            isPlayerPresented = false
            teardownObserver?(.playerDetached)

            releaseLeaseOnce()

            reportFailure = nil
            presentationControllerEpochs.removeAll()
            activePresentationController = nil
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
        let presentingPlayerController = playerController
        let presentationGeneration = playbackGeneration
        presentationEpoch &+= 1
        let attemptedPresentationEpoch = presentationEpoch
        activePresentationController = nil
        beginPresentationTransition()
        anchorController.present(
            presentingPlayerController,
            animated: true
        ) { [weak self, weak presentingPlayerController] in
            guard let presentingPlayerController else { return }
            guard let self else { return }
            guard self.phase == .ready,
                  self.playbackGeneration == presentationGeneration,
                  self.presentationEpoch == attemptedPresentationEpoch,
                  self.playerController === presentingPlayerController else {
                // A terminal stop or replacement playback may have completed
                // while UIKit still owned the presentation callback. Dismiss
                // only a controller retired by that terminal boundary. An
                // older attempt for the still-current controller must not
                // dismiss a newer retry of that controller.
                if self.playbackGeneration != presentationGeneration
                    || self.playerController !== presentingPlayerController {
                    presentingPlayerController.dismiss(animated: false)
                }
                return
            }
            let didPresent =
                presentingPlayerController.presentingViewController != nil
            self.isPlayerPresented = didPresent
            if didPresent {
                self.registerPresentationController(
                    presentingPlayerController.presentationController,
                    epoch: attemptedPresentationEpoch
                )
            } else if self.phase == .ready, self.canPresent {
                // Keep one retry available on the visible poster if UIKit
                // declines a presentation instead of losing the request.
                self.hasPendingPresentation = true
            }
            self.finishPresentationTransition()
        }
        registerPresentationController(
            presentingPlayerController.presentationController,
            epoch: attemptedPresentationEpoch
        )
    }

    private func dismissPlayerControllerIfNeeded(
        _ dismissingPlayerController: AVPlayerViewController,
        generation: UInt64
    ) async {
        await waitForPresentationTransition()
        guard dismissingPlayerController.presentingViewController != nil
                || isPlayerPresented else {
            finishModalDismissal()
            return
        }

        beginPresentationTransition()
        dismissingPlayerController.dismiss(animated: false) {
            [weak self, weak dismissingPlayerController] in
            guard let self,
                  let dismissingPlayerController,
                  self.playbackGeneration == generation,
                  self.playerController === dismissingPlayerController else {
                return
            }
            self.finishModalDismissal()
            self.finishPresentationTransition()
        }
        await waitForPresentationTransition()
        // The bounded wait may have expired because UIKit stopped delivering
        // callbacks during backgrounding. State reconciliation is idempotent;
        // the caller now detaches the AVPlayer graph before releasing its
        // application-owned plaintext lease.
        finishModalDismissal()
        finishPresentationTransition()
    }

    func finishModalDismissal() {
        presentationEpoch &+= 1
        presentationControllerEpochs.removeAll()
        activePresentationController = nil
        hasPendingPresentation = false
        player?.pause()
        isPlayerPresented = false
    }

    /// Notify the application only for a completed user dismissal, never a
    /// canceled gesture or terminal background/selection teardown. Consume the
    /// callback before calling out because closing the outer viewer reenters
    /// requestStop synchronously.
    private func finishUserDismissal() {
        let onDismissal = phase == .ready ? reportUserDismissal : nil
        reportUserDismissal = nil
        finishModalDismissal()
        finishPresentationTransition()
        onDismissal?()
    }

    func completeFullScreenDismissal(
        for controller: AVPlayerViewController,
        transition: (playbackGeneration: UInt64, presentationEpoch: UInt64),
        isCancelled: Bool
    ) {
        guard phase == .ready,
              playbackGeneration == transition.playbackGeneration,
              presentationEpoch == transition.presentationEpoch,
              playerController === controller else { return }
        if isCancelled {
            finishPresentationTransition()
        } else {
            finishUserDismissal()
        }
    }

    private func registerPresentationController(
        _ controller: UIPresentationController?,
        epoch: UInt64
    ) {
        guard let controller,
              epoch == presentationEpoch,
              controller.presentedViewController === playerController else {
            return
        }
        presentationControllerEpochs[ObjectIdentifier(controller)] = (
            controller: controller,
            epoch: epoch
        )
        activePresentationController = controller
        controller.delegate = self
    }

    private func beginPresentationTransition() {
        isPresentationTransitionActive = true
    }

    private func finishPresentationTransition() {
        guard isPresentationTransitionActive else { return }
        isPresentationTransitionActive = false
    }

    private func waitForPresentationTransition() async {
        guard isPresentationTransitionActive else { return }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.terminalTransitionWaitLimit)
        while isPresentationTransitionActive, clock.now < deadline {
            do {
                try await Task.sleep(for: Self.terminalTransitionPollInterval)
            } catch {
                break
            }
        }

        // Terminal teardown owns the final state. If UIKit did not finish the
        // transition inside the bound, force the local transition gate open so
        // player/item detachment and lease release can still complete.
        finishPresentationTransition()
    }

    private func releaseLeaseOnce() {
        guard !didReleasePlayerLease else { return }
        didReleasePlayerLease = true
        let release = releasePlayerLease
        releasePlayerLease = nil
        release?()
        teardownObserver?(.leaseReleased)
    }

    func beginFullScreenDismissal(
        for playerViewController: AVPlayerViewController
    ) -> (playbackGeneration: UInt64, presentationEpoch: UInt64)? {
        guard phase == .ready,
              playerViewController === self.playerController else { return nil }
        beginModalDismissal()
        return (playbackGeneration, presentationEpoch)
    }

    public func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator:
            any UIViewControllerTransitionCoordinator
    ) {
        guard let transition = beginFullScreenDismissal(
            for: playerViewController
        ) else { return }
        coordinator.animate(alongsideTransition: nil) {
            [weak self, weak playerViewController] context in
            guard let self, let playerViewController else { return }
            self.completeFullScreenDismissal(
                for: playerViewController,
                transition: transition,
                isCancelled: context.isCancelled
            )
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

    public func presentationControllerWillDismiss(
        _ presentationController: UIPresentationController
    ) {
        guard phase == .ready,
              presentationController.presentedViewController === playerController else {
            return
        }
        let identifier = ObjectIdentifier(presentationController)
        guard let registration = presentationControllerEpochs[identifier],
              registration.controller === presentationController,
              registration.epoch == presentationEpoch,
              activePresentationController === presentationController else {
            return
        }
        beginModalDismissal()
    }

    public func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        guard presentationController.presentedViewController === playerController else {
            return
        }
        let identifier = ObjectIdentifier(presentationController)
        guard let registration = presentationControllerEpochs[identifier],
              registration.controller === presentationController,
              registration.epoch == presentationEpoch,
              activePresentationController === presentationController else {
            return
        }
        finishUserDismissal()
    }

    func presentationAnchorDidAppear(
        _ controller: VaultEncryptedVideoPresentationAnchorViewController
    ) {
        attachPresentationAnchor(controller)
        isAnchorReadyForPresentation = true
        // UIKit can restore the presenter without sending every adaptive-
        // presentation callback (for example AVKit's own Done route). The
        // stable root anchor is the final source of truth that the modal is no
        // longer attached, so close the outer viewer as well.
        if isPlayerPresented,
           playerController.presentingViewController == nil {
            finishUserDismissal()
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
    var presentationTransitionIsActive: Bool {
        isPresentationTransitionActive
    }

    func registerPresentationControllerForTesting(
        _ controller: UIPresentationController
    ) {
        registerPresentationController(controller, epoch: presentationEpoch)
    }
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

/// Activates one validated local video without introducing another playback
/// screen. The native player's dismissal closes the application-owned viewer.
@MainActor
public struct VaultEncryptedVideoPlayerView: View {
    @ObservedObject private var session: VaultEncryptedVideoPlaybackSession
    private let playback: VaultPreparedVideoPlayback
    private let onPlayerWillAttach: () -> Bool
    private let onPlayerReleased: () -> Void
    private let onFailure: ((VaultPreparedVideoPlaybackError) -> Void)?
    private let onDismissal: () -> Void

    public init(
        session: VaultEncryptedVideoPlaybackSession,
        playback: VaultPreparedVideoPlayback,
        onPlayerWillAttach: @escaping () -> Bool = { true },
        onPlayerReleased: @escaping () -> Void = {},
        onFailure: ((VaultPreparedVideoPlaybackError) -> Void)? = nil,
        onDismissal: @escaping () -> Void
    ) {
        self.session = session
        self.playback = playback
        self.onPlayerWillAttach = onPlayerWillAttach
        self.onPlayerReleased = onPlayerReleased
        self.onFailure = onFailure
        self.onDismissal = onDismissal
    }

    public var body: some View {
        Color.clear
        .onAppear {
            session.activate(
                playback: playback,
                onPlayerWillAttach: onPlayerWillAttach,
                onPlayerReleased: onPlayerReleased,
                onFailure: onFailure,
                onDismissal: onDismissal
            )
        }
    }
}
