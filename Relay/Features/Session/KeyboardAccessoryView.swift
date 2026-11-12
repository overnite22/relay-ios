import RelayKit
import UIKit

/// Barre au-dessus du clavier : touches absentes du clavier iOS et modificateurs collants.
final class KeyboardAccessoryView: UIInputView {
    weak var screen: RemoteScreenView?
    private var ctrl = false { didSet { refresh() } }
    private var alt = false { didSet { refresh() } }
    private var ctrlButton: UIButton?
    private var altButton: UIButton?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 46), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 46),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 34),
        ])
        let ctrlButton = makeButton("Ctrl", id: "keyCtrl") { [weak self] in self?.ctrl.toggle() }
        let altButton = makeButton("Alt", id: "keyAlt") { [weak self] in self?.alt.toggle() }
        self.ctrlButton = ctrlButton
        self.altButton = altButton
        let keys: [(String, String, Int)] = [
            ("Échap", "keyEsc", Keysym.escape), ("Tab", "keyTab", Keysym.tab),
            ("←", "keyLeft", Keysym.left), ("↑", "keyUp", Keysym.up), ("↓", "keyDown", Keysym.down), ("→", "keyRight", Keysym.right),
            ("Début", "keyHome", Keysym.home), ("Fin", "keyEnd", Keysym.end),
            ("Pg↑", "keyPageUp", Keysym.pageUp), ("Pg↓", "keyPageDown", Keysym.pageDown), ("Suppr", "keyDelete", Keysym.delete),
        ]
        stack.addArrangedSubview(makeButton("Échap", id: "keyEsc") { [weak self] in self?.screen?.sendSpecial(Keysym.escape) })
        stack.addArrangedSubview(ctrlButton)
        stack.addArrangedSubview(altButton)
        for (title, id, sym) in keys.dropFirst() {
            stack.addArrangedSubview(makeButton(title, id: id) { [weak self] in self?.screen?.sendSpecial(sym) })
        }
        for symbol in ["|", "~", "/", "-", "`", "\\"] {
            stack.addArrangedSubview(makeButton(symbol, id: "keyChar\(symbol.unicodeScalars.first?.value ?? 0)") { [weak self] in
                self?.screen?.insertText(symbol)
            })
        }
        let fn = makeButton("F1–F12", id: "keyFn") {}
        fn.menu = UIMenu(children: (1...12).map { n in
            UIAction(title: "F\(n)") { [weak self] _ in self?.screen?.sendSpecial(Keysym.function(n)) }
        })
        fn.showsMenuAsPrimaryAction = true
        stack.addArrangedSubview(fn)
        stack.addArrangedSubview(makeButton("Masquer", id: "keyHide") { [weak self] in _ = self?.screen?.resignFirstResponder() })
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 46) }

    /// Modificateurs actifs pour la prochaine touche, puis relâchés.
    func consumeModifiers() -> [Int] {
        var out: [Int] = []
        if ctrl { out.append(Keysym.controlLeft) }
        if alt { out.append(Keysym.altLeft) }
        ctrl = false
        alt = false
        return out
    }

    private func refresh() {
        ctrlButton?.isSelected = ctrl
        altButton?.isSelected = alt
        for (button, on) in [(ctrlButton, ctrl), (altButton, alt)] {
            button?.configuration?.baseBackgroundColor = on ? .tintColor : .secondarySystemFill
            button?.configuration?.baseForegroundColor = on ? .white : .label
        }
    }

    private func makeButton(_ title: String, id: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = .secondarySystemFill
        config.baseForegroundColor = .label
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .medium)
            return a
        }
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in
            UIDevice.current.playInputClick()
            action()
        })
        button.accessibilityIdentifier = id
        button.accessibilityLabel = title
        return button
    }
}

extension KeyboardAccessoryView: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
