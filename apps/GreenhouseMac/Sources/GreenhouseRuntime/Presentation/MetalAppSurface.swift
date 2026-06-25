import AppKit
import CoreImage
import GameController
import MetalKit
import SwiftUI

public struct MetalAppSurface: NSViewRepresentable {
    public let session: AppStreamSession

    public init(session: AppStreamSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> MetalAppSurfaceView {
        MetalAppSurfaceView(session: session)
    }

    public func updateNSView(_ nsView: MetalAppSurfaceView, context: Context) {
        nsView.use(session: session)
    }
}

@MainActor
public final class MetalAppSurfaceView:
    MTKView,
    MTKViewDelegate,
    @preconcurrency NSTextInputClient
{
    private var streamSession: AppStreamSession
    private var imageContext: CIContext!
    private var commandQueue: MTLCommandQueue!
    private var tracking: NSTrackingArea?
    private var resizeWorkItem: DispatchWorkItem?
    private var keyWindowObserver: NSObjectProtocol?
    private var markedText = NSAttributedString()
    private lazy var clientInputContext = NSTextInputContext(client: self)

    init(session: AppStreamSession) {
        streamSession = session
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        guard let device else {
            fatalError("Metal is required for Greenhouse app windows")
        }
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = self
        imageContext = CIContext(mtlDevice: device)
        commandQueue = device.makeCommandQueue()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
    }

    public override var acceptsFirstResponder: Bool { true }

    func use(session: AppStreamSession) {
        guard streamSession !== session else { return }
        streamSession = session
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
        }
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.streamSession.focus()
                ControllerRouter.shared.focus(self.streamSession)
                self.window?.makeFirstResponder(self)
            }
        }
    }

    public override func updateTrackingAreas() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let newTracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self
        )
        addTrackingArea(newTracking)
        tracking = newTracking
        super.updateTrackingAreas()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleResize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        scheduleResize()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let pixelBuffer = streamSession.model.pixelBuffer else {
            return
        }
        let sequence = streamSession.model.frameSequence
        let presentationTime = streamSession.model.presentationTime

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let source = image.extent
        let destination = CGRect(origin: .zero, size: drawableSize)
        let scale = min(
            destination.width / source.width,
            destination.height / source.height
        )
        let scaled = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let x = (destination.width - scaled.extent.width) / 2
        let y = (destination.height - scaled.extent.height) / 2
        let positioned = scaled.transformed(
            by: CGAffineTransform(translationX: x, y: y)
        )

        imageContext.render(
            positioned,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: destination,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak streamSession] _ in
            guard let streamSession else { return }
            Task { @MainActor in
                let latency = streamSession.presentationLatencyMilliseconds(
                    for: presentationTime,
                    hostNowNanos: DispatchTime.now().uptimeNanoseconds
                )
                streamSession.model.markPresented(
                    sequence: sequence,
                    latencyMilliseconds: latency
                )
            }
        }
        commandBuffer.commit()
    }

    public override func becomeFirstResponder() -> Bool {
        streamSession.focus()
        ControllerRouter.shared.focus(streamSession)
        return true
    }

    public override func resignFirstResponder() -> Bool {
        ControllerRouter.shared.blur(streamSession)
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        sendPointer(event, action: 0)
    }

    public override func mouseDragged(with event: NSEvent) {
        sendPointer(event, action: 2)
    }

    public override func mouseUp(with event: NSEvent) {
        sendPointer(event, action: 1)
    }

    public override func rightMouseDown(with event: NSEvent) {
        sendPointer(event, action: 0)
    }

    public override func rightMouseDragged(with event: NSEvent) {
        sendPointer(event, action: 2)
    }

    public override func rightMouseUp(with event: NSEvent) {
        sendPointer(event, action: 1)
    }

    public override func mouseMoved(with event: NSEvent) {
        sendPointer(event, action: 7)
    }

    public override func scrollWheel(with event: NSEvent) {
        sendPointer(
            event,
            action: 8,
            scrollX: event.scrollingDeltaX,
            scrollY: event.scrollingDeltaY
        )
    }

    public override func keyDown(with event: NSEvent) {
        if let androidKey = AndroidKeyMap.keyCode(for: event.keyCode) {
            streamSession.key(
                action: 0,
                keyCode: androidKey,
                metaState: AndroidKeyMap.metaState(for: event.modifierFlags),
                repeatCount: event.isARepeat ? 1 : 0
            )
        } else {
            interpretKeyEvents([event])
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard let androidKey = AndroidKeyMap.keyCode(for: event.keyCode) else {
            return
        }
        streamSession.key(
            action: 1,
            keyCode: androidKey,
            metaState: AndroidKeyMap.metaState(for: event.modifierFlags)
        )
    }

    public override func insertText(_ insertString: Any) {
        commitText(insertString)
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        markedText = NSAttributedString()
        commitText(string)
    }

    public func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        if let attributed = string as? NSAttributedString {
            markedText = attributed
        } else if let text = string as? String {
            markedText = NSAttributedString(string: text)
        } else {
            markedText = NSAttributedString()
        }
    }

    public func unmarkText() {
        markedText = NSAttributedString()
    }

    public func selectedRange() -> NSRange {
        NSRange(location: 0, length: 0)
    }

    public func markedRange() -> NSRange {
        markedText.length == 0
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: markedText.length)
    }

    public func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    public func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        guard markedText.length > 0,
              range.location != NSNotFound,
              NSMaxRange(range) <= markedText.length else {
            return nil
        }
        actualRange?.pointee = range
        return markedText.attributedSubstring(from: range)
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    public func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        actualRange?.pointee = range
        guard let window else { return .zero }
        let localCaret = NSRect(
            x: bounds.midX,
            y: bounds.midY,
            width: 1,
            height: 20
        )
        let windowRect = convert(localCaret, to: nil)
        return window.convertToScreen(windowRect)
    }

    public func characterIndex(for point: NSPoint) -> Int {
        0
    }

    public override var inputContext: NSTextInputContext? {
        clientInputContext
    }

    public override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            streamSession.key(action: 0, keyCode: 66)
            streamSession.key(action: 1, keyCode: 66)
        case #selector(NSResponder.deleteBackward(_:)):
            streamSession.key(action: 0, keyCode: 67)
            streamSession.key(action: 1, keyCode: 67)
        default:
            super.doCommand(by: selector)
        }
    }

    private func sendPointer(
        _ event: NSEvent,
        action: Int,
        scrollX: Double = 0,
        scrollY: Double = 0
    ) {
        guard let point = guestPoint(for: event) else { return }
        streamSession.pointer(
            action: action,
            point: point,
            buttons: AndroidPointerMap.buttons(for: event),
            deltaX: event.deltaX,
            deltaY: event.deltaY,
            scrollX: scrollX,
            scrollY: scrollY
        )
    }

    private func commitText(_ value: Any) {
        if let text = value as? String {
            streamSession.text(text)
        } else if let attributed = value as? NSAttributedString {
            streamSession.text(attributed.string)
        }
    }

    private func guestPoint(for event: NSEvent) -> CGPoint? {
        let videoWidth = streamSession.model.videoWidth
        let videoHeight = streamSession.model.videoHeight
        guard videoWidth > 0, videoHeight > 0 else { return nil }

        let local = convert(event.locationInWindow, from: nil)
        let source = CGSize(width: videoWidth, height: videoHeight)
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        let contentSize = CGSize(
            width: source.width * scale,
            height: source.height * scale
        )
        let origin = CGPoint(
            x: (bounds.width - contentSize.width) / 2,
            y: (bounds.height - contentSize.height) / 2
        )
        let x = (local.x - origin.x) / scale
        let y = (contentSize.height - (local.y - origin.y)) / scale
        guard x >= 0, y >= 0, x < source.width, y < source.height else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    private func scheduleResize() {
        resizeWorkItem?.cancel()
        guard let window else { return }
        let scale = window.backingScaleFactor
        let width = max(Int(bounds.width * scale), 320)
        let height = max(Int(bounds.height * scale), 240)
        let density = max(Int(160 * scale), 160)
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.streamSession.resize(
                    width: width,
                    height: height,
                    densityDpi: density
                )
            }
        }
        resizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}

private enum AndroidPointerMap {
    static func buttons(for event: NSEvent) -> Int {
        var buttons = 0
        if NSEvent.pressedMouseButtons & 1 != 0 { buttons |= 1 }
        if NSEvent.pressedMouseButtons & 2 != 0 { buttons |= 2 }
        if NSEvent.pressedMouseButtons & 4 != 0 { buttons |= 4 }
        return buttons
    }
}

private enum AndroidKeyMap {
    static func keyCode(for macKeyCode: UInt16) -> Int? {
        switch macKeyCode {
        case 36: 66 // Return
        case 48: 61 // Tab
        case 49: 62 // Space
        case 51: 67 // Delete
        case 53: 111 // Escape / Back
        case 115: 122 // Home
        case 119: 123 // End
        case 123: 21 // Left
        case 124: 22 // Right
        case 125: 20 // Down
        case 126: 19 // Up
        default: nil
        }
    }

    static func metaState(for flags: NSEvent.ModifierFlags) -> Int {
        var state = 0
        if flags.contains(.shift) { state |= 0x1 }
        if flags.contains(.control) { state |= 0x1000 }
        if flags.contains(.option) { state |= 0x2 }
        if flags.contains(.command) { state |= 0x10000 }
        return state
    }
}

@MainActor
private final class ControllerRouter {
    static let shared = ControllerRouter()

    private weak var session: AppStreamSession?
    private var observers: [NSObjectProtocol] = []
    private var lastButtonMask = 0

    private init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.configure(notification.object as? GCController)
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateFocusedSessionStatus(focused: true)
                }
            }
        )
        for controller in GCController.controllers() {
            configure(controller)
        }
        GCController.startWirelessControllerDiscovery()
    }

    func focus(_ session: AppStreamSession) {
        if self.session !== session {
            lastButtonMask = 0
        }
        self.session = session
        updateFocusedSessionStatus(focused: true)
    }

    func blur(_ session: AppStreamSession) {
        if self.session === session {
            updateFocusedSessionStatus(focused: false)
            self.session = nil
        }
    }

    private func configure(_ controller: GCController?) {
        guard let gamepad = controller?.extendedGamepad else { return }
        updateFocusedSessionStatus(focused: session != nil)
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            Task { @MainActor in
                guard let self else { return }
                let buttonMask = Self.buttonMask(gamepad)
                let keyChanges = Self.controllerKeyChanges(
                    from: self.lastButtonMask,
                    to: buttonMask
                )
                self.lastButtonMask = buttonMask
                self.session?.controller([
                    "leftX": gamepad.leftThumbstick.xAxis.value,
                    "leftY": -gamepad.leftThumbstick.yAxis.value,
                    "rightX": gamepad.rightThumbstick.xAxis.value,
                    "rightY": -gamepad.rightThumbstick.yAxis.value,
                    "leftTrigger": gamepad.leftTrigger.value,
                    "rightTrigger": gamepad.rightTrigger.value,
                    "hatX": gamepad.dpad.xAxis.value,
                    "hatY": -gamepad.dpad.yAxis.value,
                    "buttons": buttonMask,
                    "keys": keyChanges
                ])
            }
        }
    }

    private func updateFocusedSessionStatus(focused: Bool) {
        let controller = GCController.controllers().first
        session?.model.setControllerStatus(
            connected: controller != nil,
            focused: focused && controller != nil,
            name: controller?.vendorName
        )
    }

    private static func buttonMask(_ gamepad: GCExtendedGamepad) -> Int {
        var mask = 0
        if gamepad.buttonA.isPressed { mask |= 1 }
        if gamepad.buttonB.isPressed { mask |= 2 }
        if gamepad.buttonX.isPressed { mask |= 4 }
        if gamepad.buttonY.isPressed { mask |= 8 }
        if gamepad.leftShoulder.isPressed { mask |= 64 }
        if gamepad.rightShoulder.isPressed { mask |= 128 }
        return mask
    }

    private static func controllerKeyChanges(
        from oldMask: Int,
        to newMask: Int
    ) -> [[String: Int]] {
        let mappings = [
            (mask: 1, keyCode: 96),
            (mask: 2, keyCode: 97),
            (mask: 4, keyCode: 99),
            (mask: 8, keyCode: 100),
            (mask: 64, keyCode: 102),
            (mask: 128, keyCode: 103)
        ]
        return mappings.compactMap { mapping in
            let wasPressed = oldMask & mapping.mask != 0
            let isPressed = newMask & mapping.mask != 0
            guard wasPressed != isPressed else { return nil }
            return [
                "action": isPressed ? 0 : 1,
                "keyCode": mapping.keyCode,
                "source": 0x0000_0401
            ]
        }
    }
}
