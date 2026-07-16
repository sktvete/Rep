import Foundation

enum ProgressChartScale {
    static func niceYDomain(
        for values: [Double],
        minimumPadding: Double = 1
    ) -> ClosedRange<Double>? {
        let validValues = values.filter { $0.isFinite && $0 >= 0 }
        guard let rawMin = validValues.min(), let rawMax = validValues.max() else { return nil }
        let safeMinimumPadding = minimumPadding.isFinite ? max(minimumPadding, 0) : 1

        if rawMin == rawMax {
            let pad = max(safeMinimumPadding, abs(rawMin) * 0.05, 1)
            let lower = rawMin - pad
            let upper = rawMax + pad
            guard lower.isFinite, upper.isFinite, lower < upper else { return nil }
            return lower...upper
        }

        let span = rawMax - rawMin
        guard span.isFinite, span > 0 else { return nil }
        let pad = max(span * 0.12, safeMinimumPadding)
        let paddedSpan = span + (pad * 2)
        guard pad.isFinite, paddedSpan.isFinite else { return nil }
        let step = niceStep(for: paddedSpan)
        let lower = floor((rawMin - pad) / step) * step
        let upper = ceil((rawMax + pad) / step) * step
        guard lower.isFinite, upper.isFinite else { return nil }
        guard lower < upper else { return nil }
        return lower...upper
    }

    static func axisStride(for domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        return span.isFinite ? niceStep(for: span) : 1
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
        guard span.isFinite, span > 0 else { return 1 }
        let rough = span / 4
        let magnitude = pow(10, floor(log10(rough)))
        guard magnitude.isFinite, magnitude > 0 else { return 1 }
        let normalized = rough / magnitude
        let nice: Double
        if normalized <= 1 { nice = 1 }
        else if normalized <= 2 { nice = 2 }
        else if normalized <= 5 { nice = 5 }
        else { nice = 10 }
        return max(nice * magnitude, 0.1)
    }
}
