import RelayKit
import UIKit

/// Mode de pointage sur écran tactile.
enum PointerMode: String, CaseIterable, Identifiable {
    /// Le doigt déplace le pointeur comme un pavé tactile ; tap = clic au pointeur.
    case touchpad
    /// Le doigt clique là où il touche.
    case direct

    var id: String { rawValue }
    var title: String { self == .touchpad ? "Pavé tactile" : "Toucher direct" }
    var symbol: String { self == .touchpad ? "rectangle.and.hand.point.up.left" : "hand.tap" }
}

/// Écran distant : affiche les trames, gère zoom, gestes, clavier logiciel et clavier matériel.
final class RemoteScreenView: UIView, UIKeyInput, UIGestureRecognizerDelegate {
    weak var engine: GuacEngine?
    var mode: PointerMode = .touchpad {
        didSet { updateCursorLayer() }
    }
    /// Appelé quand le clavier logiciel apparaît ou disparaît.
    var onKeyboardChange: ((Bool) -> Void)?

    private let screenLayer = CALayer()
    private let cursorLayer = CALayer()
    private let fallbackCursor = CAShapeLayer()
    private var remoteSize = CGSize.zero
    private var zoom: CGFloat = 1
    private var pan = CGPoint.zero
    private var pointer = CGPoint(x: 20, y: 20)
    private var buttons: MouseButtons = []
    private var cursorHotspot = CGPoint.zero
    private var scrollAccumulator: CGFloat = 0
    private var pinchStart: (zoom: CGFloat, pan: CGPoint, focus: CGPoint) = (1, .zero, .zero)
    private var panStart = CGPoint.zero
    private var pressedKeys: [Int: Int] = [:]
    let accessory = KeyboardAccessoryView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isMultipleTouchEnabled = true
        accessibilityIdentifier = "remoteScreen"
        screenLayer.magnificationFilter = .linear
        screenLayer.minificationFilter = .trilinear
        screenLayer.contentsGravity = .resize
        layer.addSublayer(screenLayer)
        fallbackCursor.path = UIBezierPath(ovalIn: CGRect(x: -6, y: -6, width: 12, height: 12)).cgPath
        fallbackCursor.fillColor = UIColor.white.withAlphaComponent(0.85).cgColor
        fallbackCursor.strokeColor = UIColor.black.cgColor
        fallbackCursor.lineWidth = 1.5
        cursorLayer.addSublayer(fallbackCursor)
        cursorLayer.magnificationFilter = .nearest
        layer.addSublayer(cursorLayer)
        installGestures()
        accessory.screen = self
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Affichage

    func show(_ frame: GuacEngine.Frame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        screenLayer.contents = frame.image
        if frame.size != remoteSize {
            remoteSize = frame.size
            if pointer.x > remoteSize.width || pointer.y > remoteSize.height {
                pointer = CGPoint(x: remoteSize.width / 2, y: remoteSize.height / 2)
            }
            layoutScreen()
        }
        CATransaction.commit()
    }

    func setCursor(_ cursor: GuacEngine.Cursor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.contents = cursor.image
        cursorHotspot = cursor.hotspot
        fallbackCursor.isHidden = cursor.image != nil
        if let image = cursor.image {
            cursorLayer.bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        }
        updateCursorLayer()
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutScreen()
        CATransaction.commit()
    }

    private var baseScale: CGFloat {
        guard remoteSize.width > 0, remoteSize.height > 0, bounds.width > 0 else { return 1 }
        return min(bounds.width / remoteSize.width, bounds.height / remoteSize.height)
    }

    private var scale: CGFloat { baseScale * zoom }

    /// Position de l'écran distant dans la vue.
    private var screenFrame: CGRect {
        let s = scale
        let size = CGSize(width: remoteSize.width * s, height: remoteSize.height * s)
        var origin = CGPoint(x: -pan.x * s, y: -pan.y * s)
        if size.width <= bounds.width { origin.x = (bounds.width - size.width) / 2 }
        if size.height <= bounds.height { origin.y = (bounds.height - size.height) / 2 }
        return CGRect(origin: origin, size: size)
    }

    private func clampPan() {
        let s = scale
        guard s > 0 else { return }
        let visible = CGSize(width: bounds.width / s, height: bounds.height / s)
        pan.x = min(max(0, pan.x), max(0, remoteSize.width - visible.width))
        pan.y = min(max(0, pan.y), max(0, remoteSize.height - visible.height))
    }

    private func layoutScreen() {
        clampPan()
        screenLayer.frame = screenFrame
        updateCursorLayer()
    }

    private func updateCursorLayer() {
        let s = scale
        let f = screenFrame
        cursorLayer.isHidden = remoteSize == .zero
        cursorLayer.anchorPoint = .zero
        cursorLayer.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        cursorLayer.position = CGPoint(x: f.minX + (pointer.x - cursorHotspot.x) * s, y: f.minY + (pointer.y - cursorHotspot.y) * s)
        fallbackCursor.position = cursorHotspot
    }

    private func remotePoint(_ p: CGPoint) -> CGPoint {
        let f = screenFrame
        let s = max(scale, 0.0001)
        return CGPoint(x: min(max(0, (p.x - f.minX) / s), max(0, remoteSize.width - 1)),
                       y: min(max(0, (p.y - f.minY) / s), max(0, remoteSize.height - 1)))
    }

    /// Garde le pointeur visible quand l'écran est zoomé (mode pavé tactile).
    private func follow() {
        let s = scale
        guard zoom > 1.01, s > 0 else { return }
        let visible = CGSize(width: bounds.width / s, height: bounds.height / s)
        let margin = min(visible.width, visible.height) * 0.12
        if pointer.x < pan.x + margin { pan.x = pointer.x - margin }
        if pointer.x > pan.x + visible.width - margin { pan.x = pointer.x - visible.width + margin }
        if pointer.y < pan.y + margin { pan.y = pointer.y - margin }
        if pointer.y > pan.y + visible.height - margin { pan.y = pointer.y - visible.height + margin }
        layoutScreen()
    }

    func resetZoom() {
        zoom = 1
        pan = .zero
        layoutScreen()
    }

    // MARK: - Souris

    private func sendMouse() {
        engine?.mouse(x: Int(pointer.x.rounded()), y: Int(pointer.y.rounded()), buttons: buttons)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateCursorLayer()
        CATransaction.commit()
    }

    private func click(_ button: MouseButtons) {
        buttons.insert(button)
        sendMouse()
        buttons.remove(button)
        sendMouse()
    }

    private func installGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        let twoTap = UITapGestureRecognizer(target: self, action: #selector(onTwoFingerTap(_:)))
        twoTap.numberOfTouchesRequired = 2
        let long = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        long.minimumPressDuration = 0.4
        let drag = UIPanGestureRecognizer(target: self, action: #selector(onDrag(_:)))
        drag.maximumNumberOfTouches = 1
        let twoPan = UIPanGestureRecognizer(target: self, action: #selector(onTwoFingerPan(_:)))
        twoPan.minimumNumberOfTouches = 2
        twoPan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self
        twoPan.delegate = self
        for g in [tap, twoTap, long, drag, twoPan, pinch] { addGestureRecognizer(g) }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        if mode == .direct { pointer = remotePoint(g.location(in: self)) }
        click(.left)
    }

    @objc private func onTwoFingerTap(_ g: UITapGestureRecognizer) {
        if mode == .direct { pointer = remotePoint(g.location(in: self)) }
        click(.right)
    }

    @objc private func onLongPress(_ g: UILongPressGestureRecognizer) {
        let location = g.location(in: self)
        switch mode {
        case .direct:
            if g.state == .began {
                pointer = remotePoint(location)
                click(.right)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        case .touchpad:
            // Appui long puis glisser : glisser-déposer avec le bouton gauche.
            switch g.state {
            case .began:
                panStart = location
                buttons.insert(.left)
                sendMouse()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .changed:
                movePointer(by: CGPoint(x: location.x - panStart.x, y: location.y - panStart.y))
                panStart = location
            default:
                buttons.remove(.left)
                sendMouse()
            }
        }
    }

    private func movePointer(by delta: CGPoint) {
        let s = max(scale, 0.0001)
        let speed: CGFloat = 1.6
        pointer.x = min(max(0, pointer.x + delta.x / s * speed / max(zoom, 1)), max(0, remoteSize.width - 1))
        pointer.y = min(max(0, pointer.y + delta.y / s * speed / max(zoom, 1)), max(0, remoteSize.height - 1))
        sendMouse()
        follow()
    }

    @objc private func onDrag(_ g: UIPanGestureRecognizer) {
        let location = g.location(in: self)
        switch mode {
        case .touchpad:
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            movePointer(by: t)
        case .direct:
            pointer = remotePoint(location)
            switch g.state {
            case .began:
                buttons.insert(.left)
            case .ended, .cancelled, .failed:
                buttons.remove(.left)
            default:
                break
            }
            sendMouse()
        }
    }

    @objc private func onTwoFingerPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        if mode == .direct && zoom > 1.01 {
            pan.x -= t.x / scale
            pan.y -= t.y / scale
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutScreen()
            CATransaction.commit()
            return
        }
        // Molette : un cran tous les 24 points.
        scrollAccumulator += t.y
        while abs(scrollAccumulator) >= 24 {
            click(scrollAccumulator > 0 ? .scrollUp : .scrollDown)
            scrollAccumulator += scrollAccumulator > 0 ? -24 : 24
        }
        if g.state == .ended { scrollAccumulator = 0 }
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        let focus = g.location(in: self)
        if g.state == .began {
            pinchStart = (zoom, pan, remotePoint(focus))
        }
        let newZoom = min(max(1, pinchStart.zoom * g.scale), 6)
        zoom = newZoom
        let s = scale
        // Le point du bureau sous les doigts reste sous les doigts.
        pan = CGPoint(x: pinchStart.focus.x - focus.x / s, y: pinchStart.focus.y - focus.y / s)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutScreen()
        CATransaction.commit()
    }

    // MARK: - Clavier logiciel (UIKeyInput)

    override var canBecomeFirstResponder: Bool { true }
    override var inputAccessoryView: UIView? { accessory }

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var returnKeyType: UIReturnKeyType = .default

    var hasText: Bool { true }

    func insertText(_ text: String) {
        let modifiers = accessory.consumeModifiers()
        if !modifiers.isEmpty, text.unicodeScalars.count == 1, let scalar = text.lowercased().unicodeScalars.first {
            engine?.chord(modifiers, Keysym.from(scalar: scalar))
        } else {
            engine?.type(text)
        }
    }

    func deleteBackward() {
        let modifiers = accessory.consumeModifiers()
        engine?.chord(modifiers, Keysym.backspace)
    }

    func sendSpecial(_ keysym: Int) {
        let modifiers = accessory.consumeModifiers()
        engine?.chord(modifiers, keysym)
    }

    func toggleKeyboard() {
        if isFirstResponder { _ = resignFirstResponder() } else { _ = becomeFirstResponder() }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onKeyboardChange?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onKeyboardChange?(false) }
        return ok
    }

    // MARK: - Clavier matériel

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let sym = Self.keysym(for: key) else {
                unhandled.insert(press)
                continue
            }
            pressedKeys[key.keyCode.rawValue] = sym
            engine?.key(sym, pressed: true)
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releasePresses(presses, event: event, cancelled: false)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releasePresses(presses, event: event, cancelled: true)
    }

    private func releasePresses(_ presses: Set<UIPress>, event: UIPressesEvent?, cancelled: Bool) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, let sym = pressedKeys.removeValue(forKey: key.keyCode.rawValue) else {
                unhandled.insert(press)
                continue
            }
            engine?.key(sym, pressed: false)
        }
        if !unhandled.isEmpty {
            if cancelled { super.pressesCancelled(unhandled, with: event) } else { super.pressesEnded(unhandled, with: event) }
        }
    }

    static func keysym(for key: UIKey) -> Int? {
        switch key.keyCode {
        case .keyboardEscape: return Keysym.escape
        case .keyboardReturnOrEnter, .keypadEnter: return Keysym.enter
        case .keyboardTab: return Keysym.tab
        case .keyboardDeleteOrBackspace: return Keysym.backspace
        case .keyboardDeleteForward: return Keysym.delete
        case .keyboardLeftArrow: return Keysym.left
        case .keyboardRightArrow: return Keysym.right
        case .keyboardUpArrow: return Keysym.up
        case .keyboardDownArrow: return Keysym.down
        case .keyboardHome: return Keysym.home
        case .keyboardEnd: return Keysym.end
        case .keyboardPageUp: return Keysym.pageUp
        case .keyboardPageDown: return Keysym.pageDown
        case .keyboardInsert: return Keysym.insert
        case .keyboardLeftShift, .keyboardRightShift: return Keysym.shiftLeft
        case .keyboardLeftControl, .keyboardRightControl: return Keysym.controlLeft
        case .keyboardLeftAlt: return Keysym.altLeft
        case .keyboardRightAlt: return Keysym.altRight
        case .keyboardLeftGUI, .keyboardRightGUI: return Keysym.superLeft
        case .keyboardF1: return Keysym.function(1)
        case .keyboardF2: return Keysym.function(2)
        case .keyboardF3: return Keysym.function(3)
        case .keyboardF4: return Keysym.function(4)
        case .keyboardF5: return Keysym.function(5)
        case .keyboardF6: return Keysym.function(6)
        case .keyboardF7: return Keysym.function(7)
        case .keyboardF8: return Keysym.function(8)
        case .keyboardF9: return Keysym.function(9)
        case .keyboardF10: return Keysym.function(10)
        case .keyboardF11: return Keysym.function(11)
        case .keyboardF12: return Keysym.function(12)
        default:
            let useBase = key.modifierFlags.contains(.control) || key.modifierFlags.contains(.command)
            let text = useBase ? key.charactersIgnoringModifiers : key.characters
            guard let scalar = text.unicodeScalars.first else { return nil }
            let sym = Keysym.from(scalar: scalar)
            return sym == 0 ? nil : sym
        }
    }
}
