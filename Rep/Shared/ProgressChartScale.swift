import Foundation

enum ProgressChartScale {
    static func niceYDomain(
        for values: [Double],
        minimumPadding: Double = 1
    ) -> ClosedRange<Double>? {
        guard let rawMin = values.min(), let rawMax = values.max() else { return nil }

        if rawMin == rawMax {
            let pad = max(minimumPadding, abs(rawMin) * 0.05, 1)
            return (rawMin - pad)...(rawMax + pad)
        }

        let span = rawMax - rawMin
        let pad = max(span * 0.12, minimumPadding)
        let step = niceStep(for: span + (pad * 2))
        let lower = floor((rawMin - pad) / step) * step
        let upper = ceil((rawMax + pad) / step) * step
        guard lower < upper else { return (rawMin - pad)...(rawMax + pad) }
        return lower...upper
    }

    static func axisStride(for domain: ClosedRange<Double>) -> Double {
        niceStep(for: domain.upperBound - domain.lowerBound)
    }

    static func dayStride(for dates: [Date], calendar: Calendar = .autoupdatingCurrent) -> Int {
        guard let first = dates.min(), let last = dates.max() else { return 1 }
        let dayCount = max(
            1,
            calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)).day ?? 0
        ) + 1

        switch dayCount {
        case ...7: return 1
        case 8...21: return 2
        case 22...60: return 7
        case 61...180: return 14
        default: return 30
        }
    }

    private static func niceStep(for span: Double) -> Double {
        guard span > 0 else { return 1 }
        let rough = span / 4
        let magnitude = pow(10, floor(log10(rough)))
        let normalized = rough / magnitude
        let nice: Double
        if normalized <= 1 { nice = 1 }
        else if normalized <= 2 { nice = 2 }
        else if normalized <= 5 { nice = 5 }
        else { nice = 10 }
        return max(nice * magnitude, 0.1)
    }
}
