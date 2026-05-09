import Cocoa
import AVFoundation
import AVKit

/// Tiny transparent panel that loops an HDR-tagged video via plain `AVPlayer`.
///
/// HDR-tagged video must be actively *playing* (not just displayed as a static
/// frame) for macOS to commit the display into HDR mode. HDR mode is the
/// hardware capability gate — without it, gamma values > 1.0 don't push the
/// panel past SDR cap, they just stretch the SDR curve (washed darks, no real
/// nit gain). The actual brightness boost is applied separately in
/// `XDRBoostController` via `CGSetDisplayTransferByTable`.
///
/// We use plain `AVPlayer` + `AVPlayerLayer` (matches Vivid's binary exactly,
/// no `AVQueuePlayer`/`AVPlayerLooper`) and loop by seeking on end-of-item.
/// The looper class carries continuous queue-management overhead that bumps
/// CPU; the simpler form is what gets Vivid's near-zero usage.
///
/// `.canJoinAllSpaces` + `.stationary` so playback continues uninterrupted
/// across Space transitions, eliminating the brightness blink.
final class XDRPinWindow: NSPanel {
    private let player: AVPlayer
    private let playerLayer: AVPlayerLayer

    init(screen: NSScreen, hdrVideoURL: URL) {
        // Smaller pin → less per-refresh EDR compositing → lower CPU. 16
        // worked at ~8% CPU; trying 8 for further reduction. If HDR mode
        // doesn't trigger at this size, bump back up.
        let size: CGFloat = 8
        let frame = NSRect(
            x: screen.frame.maxX - size - 1,
            y: screen.frame.maxY - size - 1,
            width: size,
            height: size
        )

        let item = AVPlayerItem(url: hdrVideoURL)
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.playerLayer = AVPlayerLayer(player: player)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(frame, display: false)

        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        alphaValue = 0.02
        level = NSWindow.Level.floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer = playerLayer
        playerLayer.frame = view.bounds
        playerLayer.videoGravity = .resize
        playerLayer.wantsExtendedDynamicRangeContent = true
        contentView = view

        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false

        // Play briefly to commit HDR mode, then pause. The layer holds the
        // last frame, the player is in .paused state, decode/playback CPU
        // drops to ~0. HDR mode should stay committed because the EDR-tagged
        // sample is still visible on screen. (If HDR mode drops on pause,
        // we'll need to revert to the seek-on-end loop.)
        player.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak player] in
            player?.pause()
            print("[XDR] AVPlayer paused after 2s HDR-commit window")
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
