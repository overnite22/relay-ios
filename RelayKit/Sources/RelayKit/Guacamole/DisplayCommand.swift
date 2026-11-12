import Foundation

/// Opérations d'affichage décodées du protocole Guacamole, exécutées par le rendu (CoreGraphics côté iOS).
/// Les calques ≥ 0 sont visibles (0 = écran) ; les calques < 0 sont des tampons hors écran.
public enum DisplayCommand: Equatable, Sendable {
    case size(layer: Int, width: Int, height: Int)
    case image(layer: Int, mask: Int, x: Int, y: Int, mime: String, data: Data)
    case copy(src: Int, sx: Int, sy: Int, width: Int, height: Int, mask: Int, dst: Int, dx: Int, dy: Int)
    case transfer(src: Int, sx: Int, sy: Int, width: Int, height: Int, function: Int, dst: Int, dx: Int, dy: Int)
    case rect(layer: Int, x: Int, y: Int, width: Int, height: Int)
    case start(layer: Int, x: Int, y: Int)
    case line(layer: Int, x: Int, y: Int)
    case curve(layer: Int, cp1x: Int, cp1y: Int, cp2x: Int, cp2y: Int, x: Int, y: Int)
    case arc(layer: Int, x: Int, y: Int, radius: Int, start: Double, end: Double, negative: Bool)
    case close(layer: Int)
    case clip(layer: Int)
    case push(layer: Int)
    case pop(layer: Int)
    case reset(layer: Int)
    case identity(layer: Int)
    case transform(layer: Int, a: Double, b: Double, c: Double, d: Double, e: Double, f: Double)
    case distort(layer: Int, a: Double, b: Double, c: Double, d: Double, e: Double, f: Double)
    case cfill(layer: Int, mask: Int, r: Int, g: Int, b: Int, a: Int)
    case cstroke(layer: Int, mask: Int, cap: Int, join: Int, thickness: Int, r: Int, g: Int, b: Int, a: Int)
    case lfill(layer: Int, mask: Int, src: Int)
    case lstroke(layer: Int, mask: Int, cap: Int, join: Int, thickness: Int, src: Int)
    case dispose(layer: Int)
    case move(layer: Int, parent: Int, x: Int, y: Int, z: Int)
    case shade(layer: Int, opacity: Int)
    case cursor(hotX: Int, hotY: Int, src: Int, sx: Int, sy: Int, width: Int, height: Int)
    /// Fin d'une trame : le rendu doit être rafraîchi, puis `sync` renvoyé au serveur.
    case sync(timestamp: Int)
}

/// Modes de composition Guacamole (masque de canal) → opérations Porter-Duff.
public enum ChannelMask: Int, Sendable {
    case rin = 0x1, rout = 0x2, `in` = 0x4, atop = 0x6, out = 0x8, ratop = 0x9, xor = 0xA, rover = 0xB, src = 0xC, over = 0xE, plus = 0xF

    public init(mask: Int) { self = ChannelMask(rawValue: mask) ?? .over }
}
