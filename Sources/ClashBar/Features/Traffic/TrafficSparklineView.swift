import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

struct TrafficSparklineView: View {
    let upValues: [Int64]
    let downValues: [Int64]

    var body: some View {
        GeometryReader { geo in
            let maxY = max(1.0, Double(max(self.downValues.max() ?? 0, self.upValues.max() ?? 0)))
            let axisY = floor(geo.size.height * 0.5)
            let upperSpan = max(1, axisY - 2)
            let lowerSpan = max(1, geo.size.height - axisY - 2)
            let maxPoints = 60
            let upContext = SparklinePathContext(
                width: geo.size.width,
                axisY: axisY,
                span: upperSpan,
                maxY: maxY,
                direction: .up,
                maxPoints: maxPoints)
            let downContext = SparklinePathContext(
                width: geo.size.width,
                axisY: axisY,
                span: lowerSpan,
                maxY: maxY,
                direction: .down,
                maxPoints: maxPoints)

            let upPaths = self.paths(for: self.upValues, context: upContext)
            let downPaths = self.paths(for: self.downValues, context: downContext)

            ZStack {
                self.axisPath(width: geo.size.width, axisY: axisY)
                    .stroke(
                        self.nativeSeparator.opacity(0.55),
                        style: StrokeStyle(lineWidth: T.stroke, lineCap: .round))

                upPaths.area
                    .fill(
                        LinearGradient(
                            colors: [
                                self.nativeAccent.opacity(0.30),
                                self.nativeAccent.opacity(0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))

                downPaths.area
                    .fill(
                        LinearGradient(
                            colors: [
                                self.nativePositive.opacity(0.32),
                                self.nativePositive.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))

                upPaths.stroke
                    .stroke(
                        self.nativeAccent.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                downPaths.stroke
                    .stroke(
                        self.nativePositive.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func paths(for values: [Int64], context: SparklinePathContext) -> (stroke: Path, area: Path) {
        guard !values.isEmpty else { return (Path(), Path()) }

        var stroke = Path()
        var firstX: CGFloat = 0
        var lastX: CGFloat = 0

        for index in 0..<values.count {
            let p = self.point(at: index, in: values, context: context)
            if index == 0 {
                stroke.move(to: p)
                firstX = p.x
            } else {
                stroke.addLine(to: p)
            }
            if index == values.count - 1 {
                lastX = p.x
            }
        }

        var area = stroke
        area.addLine(to: CGPoint(x: lastX, y: context.axisY))
        area.addLine(to: CGPoint(x: firstX, y: context.axisY))
        area.closeSubpath()

        return (stroke, area)
    }

    private func point(at index: Int, in values: [Int64], context: SparklinePathContext) -> CGPoint {
        let clampedIndex = min(max(index, 0), values.count - 1)
        let offsetFromRight = values.count - 1 - clampedIndex
        let x = context.width - (CGFloat(offsetFromRight) / CGFloat(max(context.maxPoints - 1, 1)) * context.width)
        let y = self.yPosition(
            values[clampedIndex],
            axisY: context.axisY,
            span: context.span,
            maxY: context.maxY,
            direction: context.direction)
        return CGPoint(x: x, y: y)
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
        let maxPoints: Int
    }

    private enum LineDirection {
        case up
        case down
    }
}
