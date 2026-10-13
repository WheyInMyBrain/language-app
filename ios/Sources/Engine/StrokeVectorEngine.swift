import SwiftUI

public enum StrokeVectorEngine {
    /// Converts raw point arrays into a SwiftUI Path
    public static func path(for points: [[Double]]) -> Path {
        var path = Path()
        guard let first = points.first, first.count >= 2 else { return path }

        path.move(to: CGPoint(x: first[0], y: first[1]))
        for i in 1..<points.count {
            let pt = points[i]
            if pt.count >= 2 {
                path.addLine(to: CGPoint(x: pt[0], y: pt[1]))
            }
        }
        return path
    }

    /// Computes the stroke path length
    public static func length(for points: [[Double]]) -> CGFloat {
        guard points.count >= 2 else { return 200 }
        var total: CGFloat = 0
        for i in 0..<(points.count - 1) {
            let p1 = points[i]
            let p2 = points[i + 1]
            let dx = CGFloat(p2[0] - p1[0])
            let dy = CGFloat(p2[1] - p1[1])
            total += hypot(dx, dy)
        }
        return max(total * 1.25, 200)
    }

    /// Parses SVG path strings into native CoreGraphics paths
    public static func parseSVGPath(_ d: String) -> Path {
        // Simplified SVG path parser for font outline representations
        return Path { path in
            let commands = d.components(separatedBy: CharacterSet(charactersIn: "MLZmlz ")).filter { !$0.isEmpty }
            var points: [CGPoint] = []
            var i = 0
            while i < commands.count - 1 {
                if let x = Double(commands[i]), let y = Double(commands[i + 1]) {
                    points.append(CGPoint(x: x, y: y))
                    i += 2
                } else {
                    i += 1
                }
            }

            if let first = points.first {
                path.move(to: first)
                for pt in points.dropFirst() {
                    path.addLine(to: pt)
                }
                path.closeSubpath()
            }
        }
    }
}