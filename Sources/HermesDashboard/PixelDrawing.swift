import AppKit
import CoreGraphics
import CoreText

enum PixelPalette {
    static let ink = NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.07, alpha: 1)
    static let navy = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.13, alpha: 1)
    static let panel = NSColor(calibratedRed: 0.055, green: 0.08, blue: 0.16, alpha: 0.92)
    static let border = NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.34, alpha: 1)
    static let borderBright = NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.70, alpha: 1)
    static let cyan = NSColor(calibratedRed: 0.20, green: 0.87, blue: 0.86, alpha: 1)
    static let cyanDim = NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.52, alpha: 1)
    static let cream = NSColor(calibratedRed: 0.94, green: 0.87, blue: 0.72, alpha: 1)
    static let orange = NSColor(calibratedRed: 0.93, green: 0.38, blue: 0.18, alpha: 1)
    static let yellow = NSColor(calibratedRed: 0.96, green: 0.76, blue: 0.18, alpha: 1)
    static let red = NSColor(calibratedRed: 0.92, green: 0.22, blue: 0.25, alpha: 1)
    static let green = NSColor(calibratedRed: 0.46, green: 0.75, blue: 0.28, alpha: 1)
    static let violet = NSColor(calibratedRed: 0.48, green: 0.40, blue: 0.78, alpha: 1)
    static let skin = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.56, alpha: 1)
    static let hair = NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.25, alpha: 1)
    static let hairLight = NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.42, alpha: 1)
}

struct PixelPainter {
    private static let glyphs: [Character: [String]] = [
        "A": ["01110", "11011", "11011", "11111", "11011", "11011", "11011"],
        "B": ["11110", "11011", "11011", "11110", "11011", "11011", "11110"],
        "C": ["01111", "11000", "11000", "11000", "11000", "11000", "01111"],
        "D": ["11110", "11011", "11011", "11011", "11011", "11011", "11110"],
        "E": ["11111", "11000", "11000", "11110", "11000", "11000", "11111"],
        "F": ["11111", "11000", "11000", "11110", "11000", "11000", "11000"],
        "G": ["01111", "11000", "11000", "11011", "11011", "11011", "01111"],
        "H": ["11011", "11011", "11011", "11111", "11011", "11011", "11011"],
        "I": ["11111", "00110", "00110", "00110", "00110", "00110", "11111"],
        "J": ["00111", "00011", "00011", "00011", "11011", "11011", "01110"],
        "K": ["11011", "11011", "11110", "11100", "11110", "11011", "11011"],
        "L": ["11000", "11000", "11000", "11000", "11000", "11000", "11111"],
        "M": ["11011", "11111", "11111", "11011", "11011", "11011", "11011"],
        "N": ["11011", "11111", "11111", "11111", "11011", "11011", "11011"],
        "O": ["01110", "11011", "11011", "11011", "11011", "11011", "01110"],
        "P": ["11110", "11011", "11011", "11110", "11000", "11000", "11000"],
        "Q": ["01110", "11011", "11011", "11011", "11111", "01110", "00011"],
        "R": ["11110", "11011", "11011", "11110", "11100", "11011", "11011"],
        "S": ["01111", "11000", "11000", "01110", "00011", "00011", "11110"],
        "T": ["11111", "00110", "00110", "00110", "00110", "00110", "00110"],
        "U": ["11011", "11011", "11011", "11011", "11011", "11011", "01110"],
        "V": ["11011", "11011", "11011", "11011", "11011", "01110", "00100"],
        "W": ["11011", "11011", "11011", "11011", "11111", "11111", "01010"],
        "X": ["11011", "11011", "01110", "00100", "01110", "11011", "11011"],
        "Y": ["11011", "11011", "01110", "00110", "00110", "00110", "00110"],
        "Z": ["11111", "00011", "00110", "01100", "11000", "11000", "11111"],
        "0": ["01110", "11011", "11111", "11111", "11011", "11011", "01110"],
        "1": ["00110", "01110", "00110", "00110", "00110", "00110", "11111"],
        "2": ["01110", "11011", "00011", "00110", "01100", "11000", "11111"],
        "3": ["11110", "00011", "00011", "01110", "00011", "00011", "11110"],
        "4": ["00011", "00111", "01111", "11011", "11111", "00011", "00011"],
        "5": ["11111", "11000", "11000", "11110", "00011", "00011", "11110"],
        "6": ["01110", "11000", "11000", "11110", "11011", "11011", "01110"],
        "7": ["11111", "00011", "00110", "01100", "01100", "01100", "01100"],
        "8": ["01110", "11011", "11011", "01110", "11011", "11011", "01110"],
        "9": ["01110", "11011", "11011", "01111", "00011", "00011", "01110"],
        ":": ["00000", "00110", "00110", "00000", "00110", "00110", "00000"],
        ".": ["00000", "00000", "00000", "00000", "00000", "00110", "00110"],
        ",": ["00000", "00000", "00000", "00000", "00110", "00110", "01100"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        "/": ["00001", "00011", "00110", "01100", "11000", "11000", "10000"],
        "%": ["11001", "11010", "00000", "00100", "00000", "01011", "10011"],
        "$": ["00110", "01111", "11000", "01110", "00011", "11110", "00110"],
        "_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
        "&": ["01100", "11010", "01100", "01110", "11011", "11011", "01110"],
        "?": ["01110", "11011", "00011", "00110", "00110", "00000", "00110"],
        "°": ["01100", "11011", "01100", "00000", "00000", "00000", "00000"],
        "!": ["00110", "00110", "00110", "00110", "00110", "00000", "00110"]
    ]

    static func drawPixelText(_ text: String, at point: CGPoint, scale: CGFloat, color: NSColor, context: CGContext) {
        color.setFill()
        var x = point.x
        for character in text.uppercased() {
            if character == " " {
                x += scale * 4
                continue
            }
            let glyph = glyphs[character] ?? glyphs["?"]!
            for (row, line) in glyph.enumerated() {
                for (column, bit) in line.enumerated() where bit == "1" {
                    context.fill(CGRect(x: x + CGFloat(column) * scale, y: point.y + CGFloat(row) * scale, width: scale, height: scale))
                }
            }
            x += scale * 6
        }
    }

    static func pixelTextWidth(_ text: String, scale: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        for character in text.uppercased() {
            width += character == " " ? scale * 4 : scale * 6
        }
        return max(width - scale, 0)
    }

    static func drawText(_ text: String, at point: CGPoint, style: TextStyle, context: CGContext) {
        if style.fontName == TextStyle.builtInPixelFont {
            drawPixelText(text, at: point, scale: max(style.pointSize / 7, 1), color: style.color, context: context)
            return
        }

        let font = NSFont(name: style.fontName, size: style.pointSize)
            ?? NSFont(name: "Menlo", size: style.pointSize)
            ?? NSFont.monospacedSystemFont(ofSize: style.pointSize, weight: .regular)
        let attributed = NSAttributedString(string: text.uppercased(), attributes: [
            .font: font,
            .foregroundColor: style.color
        ])
        let textSize = attributed.size()
        let imageSize = CGSize(width: ceil(textSize.width + 4), height: ceil(font.ascender - font.descender + 4))
        let rasterScale: CGFloat = style.smoothRendering ? 2 : 1
        guard let imageContext = CGContext(
            data: nil,
            width: max(Int(ceil(imageSize.width * rasterScale)), 1),
            height: max(Int(ceil(imageSize.height * rasterScale)), 1),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        imageContext.scaleBy(x: rasterScale, y: rasterScale)
        imageContext.setShouldAntialias(style.smoothRendering)
        imageContext.setAllowsAntialiasing(style.smoothRendering)
        imageContext.setShouldSmoothFonts(style.smoothRendering)
        imageContext.setAllowsFontSmoothing(style.smoothRendering)
        imageContext.setShouldSubpixelPositionFonts(style.smoothRendering)
        imageContext.setAllowsFontSubpixelPositioning(style.smoothRendering)
        imageContext.setFillColor(NSColor.clear.cgColor)
        imageContext.fill(CGRect(origin: .zero, size: imageSize))
        let line = CTLineCreateWithAttributedString(attributed)
        imageContext.textPosition = CGPoint(x: 1, y: 2 - font.descender)
        CTLineDraw(line, imageContext)
        guard let image = imageContext.makeImage() else { return }
        drawAsset(image, in: CGRect(x: point.x.rounded(.toNearestOrAwayFromZero), y: point.y.rounded(.toNearestOrAwayFromZero), width: imageSize.width, height: imageSize.height), interpolation: style.smoothRendering ? .high : .none, context: context)
    }

    static func textWidth(_ text: String, style: TextStyle) -> CGFloat {
        if style.fontName == TextStyle.builtInPixelFont {
            return pixelTextWidth(text, scale: max(style.pointSize / 7, 1))
        }
        let font = NSFont(name: style.fontName, size: style.pointSize)
            ?? NSFont(name: "Menlo", size: style.pointSize)
            ?? NSFont.monospacedSystemFont(ofSize: style.pointSize, weight: .regular)
        return NSAttributedString(string: text.uppercased(), attributes: [.font: font]).size().width
    }

    static func fill(_ rect: CGRect, color: NSColor, context: CGContext) {
        color.setFill()
        context.fill(rect.integral)
    }

    static func drawFrame(_ rect: CGRect, color: NSColor = PixelPalette.border, context: CGContext, fill: NSColor? = nil) {
        if let fill { fill.setFill(); context.fill(rect) }
        color.setStroke()
        context.setLineWidth(2)
        context.stroke(rect.insetBy(dx: 1, dy: 1))
        let cut: CGFloat = 7
        color.setFill()
        for point in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX - cut, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY - cut), CGPoint(x: rect.maxX - cut, y: rect.maxY - cut)
        ] {
            context.fill(CGRect(x: point.x, y: point.y, width: cut, height: cut))
        }
    }

    static func drawProgress(_ rect: CGRect, value: Int, color: NSColor, context: CGContext) {
        // Pixel-sized slots keep the context meter legible at a glance. The
        // dark slots remain visible behind the cyan loaded blocks.
        let segments = max(Int(rect.width / 16), 1)
        let gap: CGFloat = 3
        let segmentWidth = max((rect.width - gap * CGFloat(segments - 1)) / CGFloat(segments), 1)
        let filled = Int((CGFloat(segments) * CGFloat(min(max(value, 0), 100)) / 100.0).rounded(.down))
        for index in 0..<segments {
            let x = rect.minX + CGFloat(index) * (segmentWidth + gap)
            let segmentColor = index < filled ? color : PixelPalette.navy
            fill(CGRect(x: x, y: rect.minY, width: segmentWidth, height: rect.height), color: segmentColor, context: context)
        }
    }

    static func drawWeatherIcon(at point: CGPoint, scale: CGFloat, condition _: WeatherCondition, context: CGContext) {
        let moon: [String] = [
            "000001111000000", "000111111100000", "001111111110000", "011111111111000",
            "011111111111000", "111111111111100", "111111111111100", "111111111111100",
            "111111111111100", "011111111111000", "011111111111000", "001111111110000",
            "000111111100000", "000001111000000", "000000000000000"
        ]
        let moonGold = NSColor(calibratedRed: 0.84, green: 0.62, blue: 0.30, alpha: 1)
        moonGold.setFill()
        for (row, line) in moon.enumerated() {
            for (column, bit) in line.enumerated() where bit == "1" {
                context.fill(CGRect(x: point.x + CGFloat(column) * scale, y: point.y + CGFloat(row) * scale, width: scale, height: scale))
            }
        }
        navy.setFill()
        for (row, line) in moon.enumerated() {
            for (column, bit) in line.enumerated() where bit == "1" && column > 7 {
                context.fill(CGRect(x: point.x + CGFloat(column) * scale, y: point.y + CGFloat(row) * scale, width: scale, height: scale))
            }
        }

        // A few square craters and a low cloud give the weather marker the same
        // illustrated, layered silhouette as the reference dashboard.
        let crater = NSColor(calibratedRed: 0.64, green: 0.42, blue: 0.18, alpha: 1)
        for (x, y, width, height) in [(5, 4, 2, 2), (8, 8, 2, 2), (5, 11, 1, 1)] {
            crater.setFill()
            context.fill(CGRect(x: point.x + CGFloat(x) * scale, y: point.y + CGFloat(y) * scale, width: CGFloat(width) * scale, height: CGFloat(height) * scale))
        }

        PixelPalette.borderBright.setFill()
        for (x, y, width) in [(0, 16, 5), (3, 14, 6), (8, 16, 6), (13, 15, 4)] {
            context.fill(CGRect(x: point.x + CGFloat(x) * scale, y: point.y + CGFloat(y) * scale, width: CGFloat(width) * scale, height: 2 * scale))
        }

        // Keep the weather marker within the same vertical row as the time.
        // The moon and a few stars communicate night conditions without adding
        // a second text block or pushing a cloud into the date line.
        PixelPalette.cream.setFill()
        for (x, y) in [(2, 2), (12, 5), (13, 10)] {
            context.fill(CGRect(x: point.x + CGFloat(x) * scale, y: point.y + CGFloat(y) * scale, width: scale, height: scale))
        }
    }

    static func drawStatusIcon(at point: CGPoint, kind: Int, color: NSColor, context: CGContext) {
        color.setFill()
        let s: CGFloat = 3
        switch kind % 6 {
        case 0:
            for row in 0..<7 { for column in 0..<7 where row == 0 || row == 6 || column == 0 || column == 6 || (row >= 2 && row <= 4 && column >= 2 && column <= 4) { context.fill(CGRect(x: point.x + CGFloat(column) * s, y: point.y + CGFloat(row) * s, width: s, height: s)) } }
        case 1:
            for row in 0..<7 { for column in 0..<7 where abs(row - 3) + abs(column - 3) <= 3 { context.fill(CGRect(x: point.x + CGFloat(column) * s, y: point.y + CGFloat(row) * s, width: s, height: s)) } }
        case 2:
            for row in 0..<7 { for column in 0..<7 where (row == column || row + column == 6 || (row == 3 && column > 1)) { context.fill(CGRect(x: point.x + CGFloat(column) * s, y: point.y + CGFloat(row) * s, width: s, height: s)) } }
        case 3:
            for row in 0..<7 { for column in 0..<7 where row == 0 || row == 6 || column == 0 || column == 6 || row == column { context.fill(CGRect(x: point.x + CGFloat(column) * s, y: point.y + CGFloat(row) * s, width: s, height: s)) } }
        case 4:
            for row in 0..<7 { for column in 0..<7 where column == 2 || column == 4 || (row == 1 && column == 3) || (row == 5 && column == 3) { context.fill(CGRect(x: point.x + CGFloat(column) * s, y: point.y + CGFloat(row) * s, width: s, height: s)) } }
        default:
            for row in 0..<7 { let width = row < 3 ? row + 2 : 7 - row; for column in 0..<width { context.fill(CGRect(x: point.x + CGFloat(column) * s, y: point.y + CGFloat(row) * s, width: s, height: s)) } }
        }
    }

    static func drawAvatar(at point: CGPoint, scale: CGFloat, state: AgentState, phase: Int, context: CGContext) {
        func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: NSColor) {
            fill(CGRect(x: point.x + CGFloat(x) * scale, y: point.y + CGFloat(y) * scale, width: CGFloat(width) * scale, height: CGFloat(height) * scale), color: color, context: context)
        }

        let bob = state == .working && phase % 2 == 0 ? 1 : 0
        let handOffset = state == .thinking ? -2 : (state == .done ? -4 : 0)
        rect(1, 23 + bob, 26, 4, PixelPalette.border)
        rect(4, 18 + bob, 20, 8, PixelPalette.navy)
        rect(7, 17 + bob, 14, 8, PixelPalette.hair)
        rect(9, 19 + bob, 11, 6, PixelPalette.hairLight)
        rect(10, 22 + bob, 8, 9, PixelPalette.skin)
        rect(12, 24 + bob, 2, 2, PixelPalette.ink)
        rect(17, 24 + bob, 2, 2, PixelPalette.ink)
        rect(9, 27 + bob, 11, 3, PixelPalette.orange)
        rect(7, 29 + bob, 15, 12, PixelPalette.hair)
        rect(9, 31 + bob, 11, 10, PixelPalette.cyanDim)
        rect(5, 29 + bob, 4, 11, PixelPalette.hair)
        rect(20, 29 + bob, 4, 11, PixelPalette.hair)
        rect(2, 22 + bob, 5, 11, PixelPalette.hair)
        rect(1, 23 + bob, 3, 7, PixelPalette.cyan)
        rect(0, 24 + bob, 2, 4, PixelPalette.cyanDim)
        rect(22, 28 + bob, 6, 2, PixelPalette.orange)
        rect(23, 30 + bob, 5, 2, PixelPalette.orange)
        rect(8, 40 + bob, 5, 4, PixelPalette.navy)
        rect(17, 40 + bob, 5, 4, PixelPalette.navy)
        rect(7, 44 + bob, 7, 2, PixelPalette.borderBright)
        rect(16, 44 + bob, 7, 2, PixelPalette.borderBright)

        // Terminal and the animated hand gesture make the state legible at a glance.
        rect(29, 26, 14, 16, PixelPalette.panel)
        rect(30, 27, 12, 12, PixelPalette.border)
        rect(32, 30, 6, 1, PixelPalette.cyan)
        rect(32, 33, 4, 1, PixelPalette.cyan)
        rect(32, 36, 7, 1, PixelPalette.cyanDim)
        if state == .thinking {
            rect(25, 19, 2, 2, PixelPalette.violet)
            rect(29, 16, 2, 2, PixelPalette.violet)
            rect(33, 13, 2, 2, PixelPalette.violet)
        } else if state == .done {
            rect(27, 17 + handOffset, 3, 9, PixelPalette.skin)
            rect(28, 14 + handOffset, 3, 5, PixelPalette.skin)
            rect(30, 13 + handOffset, 3, 4, PixelPalette.skin)
            rect(32, 16 + handOffset, 3, 2, PixelPalette.skin)
        } else if state == .error {
            rect(27, 17, 3, 3, PixelPalette.orange)
            rect(31, 21, 3, 3, PixelPalette.orange)
            rect(35, 17, 3, 3, PixelPalette.orange)
            rect(31, 17, 3, 3, PixelPalette.orange)
            rect(31, 25, 3, 3, PixelPalette.orange)
        } else {
            rect(25, 38 + bob, 7, 3, PixelPalette.skin)
            rect(28, 39 + bob, 5, 2, PixelPalette.skin)
        }
    }

    static func drawWallpaper(_ image: CGImage?, in rect: CGRect, alpha: CGFloat, context: CGContext) {
        if let image {
            context.saveGState()
            context.setAlpha(alpha)
            let imageWidth = CGFloat(image.width)
            let imageHeight = CGFloat(image.height)
            let scale = max(rect.width / imageWidth, rect.height / imageHeight)
            let drawSize = CGSize(width: imageWidth * scale, height: imageHeight * scale)
            let drawRect = CGRect(x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2, width: drawSize.width, height: drawSize.height)
            context.draw(image, in: drawRect)
            context.restoreGState()
        }
    }

    static func drawAsset(_ image: CGImage, in rect: CGRect, interpolation: CGInterpolationQuality = .none, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = interpolation
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    static func drawDefaultBackdrop(width: CGFloat, height: CGFloat, context: CGContext) {
        PixelPalette.ink.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        navy.setFill()
        context.fill(CGRect(x: 0, y: height * 0.60, width: width, height: height * 0.40))
    }

    private static var navy: NSColor { PixelPalette.navy }
}
