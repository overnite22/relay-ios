import CoreGraphics
import Foundation
import ImageIO
import RelayKit

/// Calque Guacamole : bitmap CoreGraphics en coordonnées « haut-gauche » (CTM retournée).
final class GuacLayer {
    let id: Int
    private(set) var width = 0
    private(set) var height = 0
    private(set) var context: CGContext
    var path = CGMutablePath()
    var pathOpen = false
    var depth = 0
    var parent = 0
    var x = 0
    var y = 0
    var z = 0
    var opacity = 255

    init(id: Int, width: Int = 0, height: Int = 0) {
        self.id = id
        context = GuacLayer.makeContext(width: width, height: height)
        self.width = width
        self.height = height
    }

    static func makeContext(width: Int, height: Int) -> CGContext {
        let w = max(width, 1)
        let h = max(height, 1)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
            ?? CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)
        guard let ctx else { preconditionFailure("CGContext indisponible") }
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.saveGState()
        return ctx
    }

    /// Redimensionne en conservant le contenu (ancré en haut à gauche).
    func resize(width: Int, height: Int) {
        guard width != self.width || height != self.height else { return }
        let old = (width: self.width, height: self.height) == (0, 0) ? nil : context.makeImage()
        let oldSize = CGSize(width: self.width, height: self.height)
        context = GuacLayer.makeContext(width: width, height: height)
        self.width = width
        self.height = height
        depth = 0
        if let old { draw(old, in: CGRect(origin: .zero, size: oldSize), mode: .copy) }
    }

    func image() -> CGImage? { width > 0 && height > 0 ? context.makeImage() : nil }

    func draw(_ image: CGImage, in rect: CGRect, mode: CGBlendMode) {
        context.saveGState()
        context.setBlendMode(mode)
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    func consumePath() -> CGPath {
        let p = path
        path = CGMutablePath()
        pathOpen = false
        return p
    }

    func push() {
        context.saveGState()
        depth += 1
    }

    func pop() {
        guard depth > 0 else { return }
        context.restoreGState()
        depth -= 1
    }

    /// Supprime l'empilement, le clip et les transformations.
    func reset() {
        while depth > 0 { pop() }
        context.restoreGState()
        context.saveGState()
        path = CGMutablePath()
        pathOpen = false
    }

    /// Ramène la CTM à l'état de base (retournement vertical seul).
    func identity() {
        context.concatenate(context.ctm.inverted())
        context.translateBy(x: 0, y: CGFloat(max(height, 1)))
        context.scaleBy(x: 1, y: -1)
    }
}

/// Affichage Guacamole complet : calques, tampons, curseur et composition.
final class GuacDisplay {
    private(set) var layers: [Int: GuacLayer] = [0: GuacLayer(id: 0)]
    private(set) var cursorImage: CGImage?
    private(set) var cursorHotspot = CGPoint.zero
    private var output: CGContext?
    private var outputSize = (0, 0)

    var size: CGSize {
        let l = layer(0)
        return CGSize(width: l.width, height: l.height)
    }

    func layer(_ id: Int) -> GuacLayer {
        if let l = layers[id] { return l }
        let l = GuacLayer(id: id)
        layers[id] = l
        return l
    }

    static func blend(_ mask: Int) -> CGBlendMode {
        switch ChannelMask(mask: mask) {
        case .rin: return .destinationIn
        case .rout: return .destinationOut
        case .in: return .sourceIn
        case .atop: return .sourceAtop
        case .out: return .sourceOut
        case .ratop: return .destinationAtop
        case .xor: return .xor
        case .rover: return .destinationOver
        case .src: return .copy
        case .over: return .normal
        case .plus: return .plusLighter
        }
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Applique une commande ; renvoie vrai si le curseur a changé.
    @discardableResult
    func apply(_ command: DisplayCommand) -> Bool {
        switch command {
        case .size(let id, let w, let h):
            layer(id).resize(width: max(0, w), height: max(0, h))
        case .image(let id, let mask, let x, let y, _, let data):
            guard let image = Self.decode(data) else { return false }
            layer(id).draw(image, in: CGRect(x: x, y: y, width: image.width, height: image.height), mode: Self.blend(mask))
        case .copy(let src, let sx, let sy, let w, let h, let mask, let dst, let dx, let dy):
            copy(src: src, rect: CGRect(x: sx, y: sy, width: w, height: h), to: dst, at: CGPoint(x: dx, y: dy), mode: Self.blend(mask))
        case .transfer(let src, let sx, let sy, let w, let h, _, let dst, let dx, let dy):
            copy(src: src, rect: CGRect(x: sx, y: sy, width: w, height: h), to: dst, at: CGPoint(x: dx, y: dy), mode: .copy)
        case .rect(let id, let x, let y, let w, let h):
            let l = layer(id)
            l.path.addRect(CGRect(x: x, y: y, width: w, height: h))
            l.pathOpen = true
        case .start(let id, let x, let y):
            let l = layer(id)
            l.path.move(to: CGPoint(x: x, y: y))
            l.pathOpen = true
        case .line(let id, let x, let y):
            let l = layer(id)
            if l.path.isEmpty { l.path.move(to: CGPoint(x: x, y: y)) } else { l.path.addLine(to: CGPoint(x: x, y: y)) }
        case .curve(let id, let c1x, let c1y, let c2x, let c2y, let x, let y):
            let l = layer(id)
            if l.path.isEmpty { l.path.move(to: CGPoint(x: c1x, y: c1y)) }
            l.path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
        case .arc(let id, let x, let y, let r, let start, let end, let negative):
            layer(id).path.addArc(center: CGPoint(x: x, y: y), radius: CGFloat(r), startAngle: start, endAngle: end, clockwise: negative)
        case .close(let id):
            let l = layer(id)
            if !l.path.isEmpty { l.path.closeSubpath() }
        case .clip(let id):
            let l = layer(id)
            let p = l.consumePath()
            guard !p.isEmpty else { return false }
            l.context.addPath(p)
            l.context.clip()
        case .push(let id):
            layer(id).push()
        case .pop(let id):
            layer(id).pop()
        case .reset(let id):
            layer(id).reset()
        case .identity(let id):
            layer(id).identity()
        case .transform(let id, let a, let b, let c, let d, let e, let f):
            layer(id).context.concatenate(CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f))
        case .distort(let id, let a, let b, let c, let d, let e, let f):
            let l = layer(id)
            l.identity()
            l.context.concatenate(CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f))
        case .cfill(let id, let mask, let r, let g, let b, let a):
            let l = layer(id)
            let p = l.consumePath()
            l.context.saveGState()
            l.context.setBlendMode(Self.blend(mask))
            l.context.setFillColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
            l.context.addPath(p)
            l.context.fillPath()
            l.context.restoreGState()
        case .cstroke(let id, let mask, let cap, let join, let thickness, let r, let g, let b, let a):
            let l = layer(id)
            let p = l.consumePath()
            l.context.saveGState()
            l.context.setBlendMode(Self.blend(mask))
            l.context.setLineCap(cap == 1 ? .round : (cap == 2 ? .square : .butt))
            l.context.setLineJoin(join == 0 ? .bevel : (join == 2 ? .round : .miter))
            l.context.setLineWidth(CGFloat(thickness))
            l.context.setStrokeColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
            l.context.addPath(p)
            l.context.strokePath()
            l.context.restoreGState()
        case .lfill(let id, let mask, let src):
            let l = layer(id)
            let p = l.consumePath()
            guard let pattern = layer(src).image() else { return false }
            l.context.saveGState()
            l.context.setBlendMode(Self.blend(mask))
            l.context.addPath(p)
            l.context.clip()
            let tile = CGRect(x: 0, y: 0, width: pattern.width, height: pattern.height)
            var ty = 0
            while ty < l.height {
                var tx = 0
                while tx < l.width {
                    l.draw(pattern, in: tile.offsetBy(dx: CGFloat(tx), dy: CGFloat(ty)), mode: Self.blend(mask))
                    tx += max(pattern.width, 1)
                }
                ty += max(pattern.height, 1)
            }
            l.context.restoreGState()
        case .lstroke(let id, let mask, let cap, let join, let thickness, _):
            // Contour par motif : rare dans guacd ; rendu en gris neutre.
            return apply(.cstroke(layer: id, mask: mask, cap: cap, join: join, thickness: thickness, r: 128, g: 128, b: 128, a: 255))
        case .dispose(let id):
            if id != 0 { layers.removeValue(forKey: id) }
        case .move(let id, let parent, let x, let y, let z):
            guard id > 0 else { return false }
            let l = layer(id)
            l.parent = parent
            l.x = x
            l.y = y
            l.z = z
        case .shade(let id, let opacity):
            layer(id).opacity = max(0, min(255, opacity))
        case .cursor(let hx, let hy, let src, let sx, let sy, let w, let h):
            guard w > 0, h > 0, let full = layer(src).image(),
                  let cropped = full.cropping(to: CGRect(x: sx, y: sy, width: w, height: h)) else {
                cursorImage = nil
                return true
            }
            cursorImage = cropped
            cursorHotspot = CGPoint(x: hx, y: hy)
            return true
        case .sync:
            break
        }
        return false
    }

    private func copy(src: Int, rect: CGRect, to dst: Int, at point: CGPoint, mode: CGBlendMode) {
        guard rect.width > 0, rect.height > 0, let full = layer(src).image(),
              let part = full.cropping(to: rect) else { return }
        layer(dst).draw(part, in: CGRect(origin: point, size: CGSize(width: part.width, height: part.height)), mode: mode)
    }

    private func absoluteOrigin(_ l: GuacLayer) -> CGPoint {
        var x = 0
        var y = 0
        var cursor: GuacLayer? = l
        var hops = 0
        while let c = cursor, c.id != 0, hops < 32 {
            x += c.x
            y += c.y
            cursor = layers[c.parent]
            hops += 1
        }
        return CGPoint(x: x, y: y)
    }

    /// Image de l'écran à présenter (calque 0 + calques visibles).
    func composite() -> CGImage? {
        let base = layer(0)
        let visible = layers.values.filter { $0.id > 0 && $0.opacity > 0 && $0.width > 0 && $0.height > 0 }
        guard !visible.isEmpty else { return base.image() }
        guard base.width > 0, base.height > 0 else { return nil }
        if output == nil || outputSize != (base.width, base.height) {
            output = GuacLayer.makeContext(width: base.width, height: base.height)
            outputSize = (base.width, base.height)
        }
        guard let out = output else { return base.image() }
        out.clear(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        func put(_ image: CGImage, _ rect: CGRect, _ alpha: CGFloat) {
            out.saveGState()
            out.setAlpha(alpha)
            out.translateBy(x: rect.minX, y: rect.maxY)
            out.scaleBy(x: 1, y: -1)
            out.draw(image, in: CGRect(origin: .zero, size: rect.size))
            out.restoreGState()
        }
        if let img = base.image() { put(img, CGRect(x: 0, y: 0, width: base.width, height: base.height), 1) }
        for l in visible.sorted(by: { ($0.z, $0.id) < ($1.z, $1.id) }) {
            guard let img = l.image() else { continue }
            let o = absoluteOrigin(l)
            put(img, CGRect(x: o.x, y: o.y, width: CGFloat(l.width), height: CGFloat(l.height)), CGFloat(l.opacity) / 255)
        }
        return out.makeImage()
    }
}
