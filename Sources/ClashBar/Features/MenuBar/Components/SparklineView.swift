import SwiftUI

struct TrafficSparklineView: View {
    let upValues: [Int64]
    let downValues: [Int64]

    var body: some View {
        GeometryReader { geo in
            let fallbackDown = [20, 13, 18, 10, 12, 6, 12, 5, 9, 7, 4, 14, 10, 15, 8, 11, 7, 9, 5, 12].map(Int64.init)
            let fallbackUp = [10, 7, 12, 8, 9, 4, 9, 3, 7, 5, 2, 10, 8, 11, 6, 8, 5, 7, 4, 9].map(Int64.init)
            let downPoints = self.downValues.isEmpty ? fallbackDown : self.downValues
            let upPoints = self.upValues.isEmpty ? fallbackUp : self.upValues
            let sharedCount = max(downPoints.count, upPoints.count)
            let normalizedDown = self.normalizePoints(downPoints, count: sharedCount)
            let normalizedUp = self.normalizePoints(upPoints, count: sharedCount)
            let maxY = max(1.0, Double(max(normalizedDown.max() ?? 0, normalizedUp.max() ?? 0)))
            let axisY = floor(geo.size.height * 0.5)
            let upperSpan = max(1, axisY - 2)
            let lowerSpan = max(1, geo.size.height - axisY - 2)
            let upContext = SparklinePathContext(
                width: geo.size.width,
                axisY: axisY,
                span: upperSpan,
                maxY: maxY,
                direction: .up)
            let downContext = SparklinePathContext(
                width: geo.size.width,
                axisY: axisY,
                span: lowerSpan,
                maxY: maxY,
                direction: .down)

            ZStack {
                self.axisPath(width: geo.size.width, axisY: axisY)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(0.55),
                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round))

                self.lineAreaPath(for: normalizedUp, context: upContext)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlAccentColor).opacity(0.22),
                                Color(nsColor: .controlAccentColor).opacity(0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))

                self.lineAreaPath(for: normalizedDown, context: downContext)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemGreen).opacity(0.24),
                                Color(nsColor: .systemGreen).opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))

                self.linePath(for: normalizedUp, context: upContext)
                    .stroke(
                        Color(nsColor: .controlAccentColor).opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                self.linePath(for: normalizedDown, context: downContext)
                    .stroke(
                        Color(nsColor: .systemGreen).opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalizePoints(_ values: [Int64], count: Int) -> [Int64] {
        guard count > 0 else { return [] }
        guard !values.isEmpty else { return Array(repeating: 0, count: count) }
        if values.count == count { return values }
        if values.count > count { return Array(values.suffix(count)) }
        return Array(repeating: values.first ?? 0, count: count - values.count) + values
    }

    private func linePath(for values: [Int64], context: SparklinePathContext) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        let count = values.count
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) / CGFloat(max(count - 1, 1)) * context.width
            let y = self.yPosition(
                value,
                axisY: context.axisY,
                span: context.span,
                maxY: context.maxY,
                direction: context.direction)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func lineAreaPath(for values: [Int64], context: SparklinePathContext) -> Path {
        var path = self.linePath(for: values, context: context)
        guard !values.isEmpty else { return path }

        path.addLine(to: CGPoint(x: context.width, y: context.axisY))
        path.addLine(to: CGPoint(x: 0, y: context.axisY))
        path.closeSubpath()
        return path
    }

    private func axisPath(width: CGFloat, axisY: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: axisY))
        path.addLine(to: CGPoint(x: width, y: axisY))
        return path
    }

    private func yPosition(
        _ value: Int64,
        axisY: CGFloat,
        span: CGFloat,
        maxY: Double,
        direction: LineDirection) -> CGFloat
    {
        let clamped = max(0.0, min(Double(value), maxY))
        let ratio = CGFloat(clamped / maxY)

        switch direction {
        case .up:
            return axisY - ratio * span
        case .down:
            return axisY + ratio * span
        }
    }

    private struct SparklinePathContext {
        let width: CGFloat
        let axisY: CGFloat
        let span: CGFloat
        let maxY: Double
        let direction: LineDirection
    }

    private enum LineDirection {
        case up
        case down
    }
}
