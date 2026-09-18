import AppKit
import Combine
import SwiftUI

/// Avoid NSHostingView as the window contentView — it fights Auto Layout and
/// crashes in `_postWindowNeedsUpdateConstraints` when the frame changes.
private final class IslandContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(local) { return hit }
        }
        return nil
    }
}

private final class IslandNSPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandPanelController {
    private var panel: IslandNSPanel?
    private var container: IslandContainerView?
    private var hosting: NSHostingView<FloatingIslandHost>?
    private let store: ConversationStore
    private let session = IslandSession()
    private let preferences: AppPreferences
    private let accounts: AIAccountStore
    private let onOpenSettings: () -> Void
    private var placementObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hotKeyMonitor: Any?
    private var localHotKeyMonitor: Any?
    private var collapseWork: DispatchWorkItem?
    private var idleWork: DispatchWorkItem?
    private var pointerInside = false
    /// Visibility of the pill chrome — independent from expand/collapse `progress`.
    private(set) var isPillVisible = true

    /// Stable panel size — never resize on expand/collapse (that was the crash).
    private let panelHeight: CGFloat = 260

    init(
        store: ConversationStore,
        preferences: AppPreferences,
        accounts: AIAccountStore = .shared,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.preferences = preferences
        self.accounts = accounts
        self.onOpenSettings = onOpenSettings
    }

    var isVisible: Bool { panel?.isVisible == true && isPillVisible }
    var isExpanded: Bool { session.progress > 0.5 }

    func toggle() {
        if !isPillVisible {
            setPillVisible(true, animated: true) { [weak self] in
                self?.expand(fromHotkey: true)
            }
            return
        }
        if isExpanded {
            collapse(animated: true)
        } else {
            expand(fromHotkey: true)
        }
    }

    func show() {
        if !isPillVisible {
            setPillVisible(true, animated: true) { [weak self] in
                self?.expand(fromHotkey: true)
            }
        } else {
            expand(fromHotkey: true)
        }
    }

    func presentPinned() {
        ensurePanel()
        session.progress = 0
        applyPlacement()
        installMonitorsIfNeeded()
        panel?.alphaValue = 1
        panel?.ignoresMouseEvents = false
        panel?.orderFrontRegardless()
        isPillVisible = preferences.pillVisibleOnLaunch
        session.isChromeVisible = preferences.pillVisibleOnLaunch
        // Even at opacity 0 the panel stays put so hover can revive it.
        restoreHoverTracking()
    }

    /// Visually hide/show the pill (opacity) without removing it from its spot.
    /// Opacity 0 still receives hover — passing the cursor brings Beacon back.
    func setPillVisible(_ visible: Bool, animated: Bool = true, completion: (() -> Void)? = nil) {
        ensurePanel()
        installMonitorsIfNeeded()
        guard panel != nil else {
            completion?()
            return
        }

        if visible == isPillVisible, session.isChromeVisible == visible {
            panel?.ignoresMouseEvents = false
            panel?.orderFrontRegardless()
            restoreHoverTracking()
            completion?()
            return
        }

        let applyChrome: () -> Void = { [weak self] in
            guard let self else { return }
            self.isPillVisible = visible
            self.preferences.pillVisibleOnLaunch = visible
            self.panel?.alphaValue = 1
            self.panel?.ignoresMouseEvents = false
            self.panel?.orderFrontRegardless()
            self.applyPlacement()

            if animated {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    self.session.isChromeVisible = visible
                }
            } else {
                self.session.isChromeVisible = visible
            }
            self.restoreHoverTracking()
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0)) {
                completion?()
            }
        }

        if !visible {
            cancelCollapse()
            cancelIdle()
            pointerInside = false
            if isExpanded {
                if animated {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                        session.progress = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: applyChrome)
                } else {
                    session.progress = 0
                    applyChrome()
                }
            } else {
                applyChrome()
            }
        } else {
            applyChrome()
        }
    }

    func togglePillVisible(animated: Bool = true) {
        setPillVisible(!isPillVisible, animated: animated)
    }

    func refreshPlacement() {
        guard panel != nil else { return }
        applyPlacement()
        refreshHosting()
    }

    private func restoreHoverTracking() {
        pointerInside = false
        DispatchQueue.main.async { [weak self] in
            self?.evaluatePointer()
        }
    }

    private func expand(fromHotkey: Bool) {
        ensurePanel()
        installMonitorsIfNeeded()
        cancelCollapse()
        cancelIdle()
        // Revive chrome if it was only visually hidden (opacity 0).
        if !session.isChromeVisible || !isPillVisible {
            isPillVisible = true
            preferences.pillVisibleOnLaunch = true
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                session.isChromeVisible = true
            }
        }
        panel?.alphaValue = 1
        panel?.ignoresMouseEvents = false
        panel?.orderFrontRegardless()
        if fromHotkey {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
            session.progress = 1
        }
        bumpIdleTimer()
    }

    private func collapse(animated: Bool) {
        cancelIdle()
        store.dismissError()
        store.dismissFlash()
        if animated {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                session.progress = 0
            }
        } else {
            session.progress = 0
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let hosting = NSHostingView(rootView: makeRoot())
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        self.hosting = hosting

        let width = CGFloat(preferences.islandMaxWidth)
        let container = IslandContainerView(frame: NSRect(x: 0, y: 0, width: width, height: panelHeight))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        self.container = container

        let panel = IslandNSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.contentView = container
        panel.isReleasedWhenClosed = false
        // Disable constraint-driven window sizing entirely.
        panel.contentMinSize = NSSize(width: width, height: panelHeight)
        panel.contentMaxSize = NSSize(width: width, height: panelHeight)
        self.panel = panel

        placementObserver = NotificationCenter.default.addObserver(
            forName: .beaconIslandPlacementChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPlacement() }
        }

        NotificationCenter.default.addObserver(
            forName: .beaconPillVisibilityPreferenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let visible = (note.userInfo?["visible"] as? Bool) ?? true
            Task { @MainActor in
                self?.setPillVisible(visible, animated: true)
            }
        }

        applyPlacement()
    }

    private func makeRoot() -> FloatingIslandHost {
        let notch = NSScreen.main?.safeAreaInsets.top ?? 0
        return FloatingIslandHost(
            store: store,
            session: session,
            preferences: preferences,
            accounts: accounts,
            notchInsetTop: notch,
            onOpenSettings: onOpenSettings,
            onUserActivity: { [weak self] in self?.bumpIdleTimer() }
        )
    }

    private func refreshHosting() {
        hosting?.rootView = makeRoot()
    }

    /// Offsets: +X = right, +Y = up. Soft clamp so negatives aren't eaten.
    private func applyPlacement() {
        guard let panel, let screen = NSScreen.main else { return }

        let width = CGFloat(preferences.islandMaxWidth)
        let height = panelHeight
        let ox = CGFloat(preferences.islandOffsetX)
        let oy = CGFloat(preferences.islandOffsetY)
        let f = screen.frame

        var x: CGFloat
        var y: CGFloat

        switch preferences.islandEdge {
        case .top:
            // oy=0 flush top; +Y into menu bar/notch; -Y down into desktop.
            x = f.midX - width / 2 + ox
            y = f.maxY - height + oy
        case .bottom:
            x = f.midX - width / 2 + ox
            y = f.minY + oy
        case .leading:
            x = f.minX + ox
            y = f.midY - height / 2 + oy
        case .trailing:
            x = f.maxX - width + ox
            y = f.midY - height / 2 + oy
        }

        let slackX = width * 0.45
        let slackY = height * 0.45
        x = min(max(x, f.minX - slackX), f.maxX - width + slackX)
        y = min(max(y, f.minY - slackY), f.maxY - height + slackY)

        let frame = NSRect(x: x, y: y, width: width, height: height)
        panel.setFrame(frame, display: true)
        panel.contentMinSize = NSSize(width: width, height: height)
        panel.contentMaxSize = NSSize(width: width, height: height)
        container?.frame = NSRect(origin: .zero, size: frame.size)
        hosting?.frame = NSRect(origin: .zero, size: frame.size)
    }

    // MARK: - Hover + hotkey

    private func installMonitorsIfNeeded() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                Task { @MainActor in self?.evaluatePointer() }
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                Task { @MainActor in self?.evaluatePointer() }
                return event
            }
        }
        if hotKeyMonitor == nil {
            hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                Task { @MainActor in self?.handleHotKey(event) }
            }
        }
        if localHotKeyMonitor == nil {
            localHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.handleHotKey(event) == true { return nil }
                return event
            }
        }
    }

    @discardableResult
    private func handleHotKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        guard flags.contains([.command, .shift]) else { return false }

        if key == "h" {
            togglePillVisible(animated: true)
            return true
        }
        if key == "b" {
            toggle()
            return true
        }
        return false
    }

    /// When collapsed, only the center pill counts as a hit — not the whole panel.
    private func hoverHitRect() -> CGRect {
        guard let panel else { return .zero }
        let f = panel.frame
        if isExpanded {
            return f.insetBy(dx: -8, dy: -8)
        }
        let pillW: CGFloat = 168
        let pillH: CGFloat = 52
        return CGRect(
            x: f.midX - pillW / 2,
            y: f.maxY - pillH - 8,
            width: pillW,
            height: pillH
        ).insetBy(dx: -10, dy: -10)
    }

    private func evaluatePointer() {
        guard panel != nil else { return }
        // Pill may be opacity 0 but must still react to hover in place.
        guard panel?.ignoresMouseEvents == false else { return }
        let mouse = NSEvent.mouseLocation
        let inside = hoverHitRect().contains(mouse)

        if inside != pointerInside {
            pointerInside = inside
            if inside {
                cancelCollapse()
                // Invisible pill → fade back in, then expand.
                if !session.isChromeVisible || !isPillVisible {
                    isPillVisible = true
                    preferences.pillVisibleOnLaunch = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        session.isChromeVisible = true
                    }
                }
                if preferences.expandOnHover, !isExpanded {
                    expand(fromHotkey: false)
                } else {
                    bumpIdleTimer()
                }
            } else {
                scheduleCollapseFromHover()
            }
        } else if inside {
            bumpIdleTimer()
        }
    }

    private func scheduleCollapseFromHover() {
        cancelCollapse()
        guard preferences.expandOnHover else { return }
        if store.isSending || !store.draft.isEmpty { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pointerInside else { return }
            if self.store.isSending || !self.store.draft.isEmpty { return }
            self.collapse(animated: true)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func bumpIdleTimer() {
        cancelIdle()
        let seconds = preferences.autoHideSeconds
        guard seconds > 0, isExpanded else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pointerInside { self.bumpIdleTimer(); return }
            if self.store.isSending || !self.store.draft.isEmpty { self.bumpIdleTimer(); return }
            self.collapse(animated: true)
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func cancelIdle() {
        idleWork?.cancel()
        idleWork = nil
    }
}
