import Foundation

struct VolumeComparison: Identifiable, Hashable, Sendable {
    var id: String { "\(label)|\(detail)" }
    let label: String
    let detail: String
    let count: Double
    let isSurprising: Bool
}

enum VolumeComparisonCatalog {
    struct Reference: Sendable {
        let singular: String
        let plural: String
        let kilograms: Double
        let surprising: Bool
    }

    /// Everyday + weird reference masses. Values are approximate real-world averages.
    static let references: [Reference] = [
        .init(singular: "house cat", plural: "house cats", kilograms: 4.5, surprising: false),
        .init(singular: "gallon of milk", plural: "gallons of milk", kilograms: 3.9, surprising: false),
        .init(singular: "bowling ball", plural: "bowling balls", kilograms: 7.3, surprising: false),
        .init(singular: "bag of cement", plural: "bags of cement", kilograms: 25, surprising: false),
        .init(singular: "golden retriever", plural: "golden retrievers", kilograms: 32, surprising: false),
        .init(singular: "adult human", plural: "adult humans", kilograms: 70, surprising: false),
        .init(singular: "washing machine", plural: "washing machines", kilograms: 75, surprising: false),
        .init(singular: "sheep", plural: "sheep", kilograms: 80, surprising: false),
        .init(singular: "refrigerator", plural: "refrigerators", kilograms: 100, surprising: false),
        .init(singular: "adult gorilla", plural: "adult gorillas", kilograms: 160, surprising: true),
        .init(singular: "motorcycle", plural: "motorcycles", kilograms: 200, surprising: false),
        .init(singular: "grand piano", plural: "grand pianos", kilograms: 400, surprising: false),
        .init(singular: "moose", plural: "moose", kilograms: 450, surprising: true),
        .init(singular: "horse", plural: "horses", kilograms: 500, surprising: false),
        .init(singular: "cow", plural: "cows", kilograms: 700, surprising: false),
        .init(singular: "smart car", plural: "smart cars", kilograms: 750, surprising: false),
        .init(singular: "hippo", plural: "hippos", kilograms: 1_500, surprising: true),
        .init(singular: "compact car", plural: "compact cars", kilograms: 1_300, surprising: false),
        .init(singular: "great white shark", plural: "great white sharks", kilograms: 1_100, surprising: true),
        .init(singular: "elephant", plural: "elephants", kilograms: 5_000, surprising: false),
        .init(singular: "school bus", plural: "school buses", kilograms: 11_000, surprising: false),
        .init(singular: "iPhone", plural: "iPhones", kilograms: 0.22, surprising: true),
        .init(singular: "brick", plural: "bricks", kilograms: 3.0, surprising: false),
        .init(singular: "large pizza", plural: "large pizzas", kilograms: 1.1, surprising: true),
        .init(singular: "capybara", plural: "capybaras", kilograms: 55, surprising: true),
        .init(singular: "anvil", plural: "anvils", kilograms: 70, surprising: true),
        .init(singular: "water cooler jug", plural: "water cooler jugs", kilograms: 19, surprising: false),
        .init(singular: "car tire", plural: "car tires", kilograms: 10, surprising: false),
        .init(singular: "adult kangaroo", plural: "adult kangaroos", kilograms: 70, surprising: true),
        .init(singular: "vending machine", plural: "vending machines", kilograms: 180, surprising: true),
        .init(singular: "baby grand piano", plural: "baby grand pianos", kilograms: 250, surprising: false),
        .init(singular: "black bear", plural: "black bears", kilograms: 180, surprising: true),
        .init(singular: "upright piano", plural: "upright pianos", kilograms: 300, surprising: false),
        .init(singular: "sofa", plural: "sofas", kilograms: 90, surprising: false),
        .init(singular: "adult ostrich", plural: "adult ostriches", kilograms: 120, surprising: true),
        .init(singular: "blue whale heart", plural: "blue whale hearts", kilograms: 180, surprising: true),
        .init(singular: "Fiat 500", plural: "Fiat 500s", kilograms: 980, surprising: false),
        .init(singular: "Steinway concert grand", plural: "Steinway concert grands", kilograms: 480, surprising: true),
        .init(singular: "full keg of beer", plural: "full kegs of beer", kilograms: 72, surprising: true),
        .init(singular: "microwave oven", plural: "microwave ovens", kilograms: 15, surprising: false),
        .init(singular: "adult flamingo", plural: "adult flamingos", kilograms: 3.5, surprising: true),
        .init(singular: "sledgehammer", plural: "sledgehammers", kilograms: 9, surprising: false),
        .init(singular: "cannonball", plural: "cannonballs", kilograms: 14, surprising: true),
        .init(singular: "medium dog", plural: "medium dogs", kilograms: 20, surprising: false),
        .init(singular: "adult lion", plural: "adult lions", kilograms: 190, surprising: true),
        .init(singular: "pickup truck", plural: "pickup trucks", kilograms: 2_400, surprising: false),
        .init(singular: "small sailboat", plural: "small sailboats", kilograms: 1_800, surprising: true),
        .init(singular: "telephone pole", plural: "telephone poles", kilograms: 900, surprising: true),
        .init(singular: "adult reindeer", plural: "adult reindeer", kilograms: 150, surprising: true),
        .init(singular: "cash register", plural: "cash registers", kilograms: 35, surprising: true),
        .init(singular: "fire hydrant", plural: "fire hydrants", kilograms: 110, surprising: true),
        .init(singular: "parking meter", plural: "parking meters", kilograms: 45, surprising: true),
        .init(singular: "adult penguin", plural: "adult penguins", kilograms: 30, surprising: true),
        .init(singular: "space toilet", plural: "space toilets", kilograms: 21, surprising: true),
        .init(singular: "museum meteorite", plural: "museum meteorites", kilograms: 250, surprising: true),
        .init(singular: "adult walrus", plural: "adult walruses", kilograms: 1_000, surprising: true),
        .init(singular: "Mini Cooper", plural: "Mini Coopers", kilograms: 1_200, surprising: false),
        .init(singular: "rubber duck (giant parade)", plural: "giant parade ducks", kilograms: 600, surprising: true),
        .init(singular: "espresso machine", plural: "espresso machines", kilograms: 12, surprising: true),
        .init(singular: "adult wombat", plural: "adult wombats", kilograms: 26, surprising: true),
        .init(singular: "traffic cone filled with concrete", plural: "concrete traffic cones", kilograms: 18, surprising: true),
        .init(singular: "adult badger", plural: "adult badgers", kilograms: 12, surprising: true),
        .init(singular: "slot machine", plural: "slot machines", kilograms: 140, surprising: true),
        .init(singular: "arcade cabinet", plural: "arcade cabinets", kilograms: 150, surprising: true),
        .init(singular: "adult manatee", plural: "adult manatees", kilograms: 500, surprising: true)
    ]

    /// One impressive (practical) comparison and one fun (surprising) comparison.
    static func comparisons(
        forKilograms volumeKilograms: Double,
        limit: Int = 2
    ) -> [VolumeComparison] {
        guard volumeKilograms > 0 else { return [] }

        let candidates = references.compactMap { reference -> (Reference, Double, Double)? in
            let count = volumeKilograms / reference.kilograms
            guard count >= 0.08, count <= 2_000_000 else { return nil }
            return (reference, count, interestScore(count: count, surprising: reference.surprising))
        }

        let impressive = candidates
            .filter { !$0.0.surprising }
            .max(by: { $0.2 < $1.2 })
        let fun = candidates
            .filter(\.0.surprising)
            .max(by: { $0.2 < $1.2 })

        var picked: [VolumeComparison] = []
        if let impressive {
            picked.append(makeComparison(reference: impressive.0, count: impressive.1))
        }
        if let fun {
            picked.append(makeComparison(reference: fun.0, count: fun.1))
        }

        // Fallback if one bucket is empty for an unusual volume.
        if picked.count < min(limit, 2) {
            let extras = candidates
                .sorted { $0.2 > $1.2 }
                .map { makeComparison(reference: $0.0, count: $0.1) }
                .filter { candidate in !picked.contains(where: { $0.id == candidate.id }) }
            picked.append(contentsOf: extras.prefix(min(limit, 2) - picked.count))
        }

        return Array(picked.prefix(limit))
    }

    private static func makeComparison(reference: Reference, count: Double) -> VolumeComparison {
        VolumeComparison(
            label: formattedCount(count),
            detail: noun(for: reference, count: count),
            count: count,
            isSurprising: reference.surprising
        )
    }

    private static func interestScore(count: Double, surprising: Bool) -> Double {
        let fractional = abs(count - count.rounded())
        // Strongly prefer whole (or nearly whole) counts over 3,05-style decimals.
        let wholeBonus: Double
        switch fractional {
        case 0..<0.03: wholeBonus = 3.0
        case 0.03..<0.08: wholeBonus = 2.2
        case 0.08..<0.15: wholeBonus = 1.0
        default: wholeBonus = 0.15
        }
        // Prefer chunky, memorable amounts — a few cars beats 847 bricks.
        let magnitudeBonus: Double
        switch count {
        case 0.5..<1.5: magnitudeBonus = 1.35
        case 1.5..<6: magnitudeBonus = 1.4
        case 6..<20: magnitudeBonus = 1.15
        case 20..<80: magnitudeBonus = 0.95
        case 0.15..<0.5: magnitudeBonus = 1.05
        default: magnitudeBonus = 0.7
        }
        let heftBonus = surprising ? 0.2 : min(0.35, log10(max(1, count * 10)) * 0.08)
        return wholeBonus + magnitudeBonus + heftBonus
    }

    private static func formattedCount(_ count: Double) -> String {
        let nearest = count.rounded()
        // Snap to a whole number whenever we're close enough to read cleanly.
        if abs(count - nearest) < 0.12, nearest >= 1 {
            return Int(nearest).formatted()
        }
        if count >= 100 {
            return count.formatted(.number.precision(.fractionLength(0)))
        }
        if count >= 10 {
            return count.formatted(.number.precision(.fractionLength(0)))
        }
        // One decimal max — never "3,05".
        return count.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func noun(for reference: Reference, count: Double) -> String {
        let display = abs(count - count.rounded()) < 0.12 ? count.rounded() : count
        return abs(display - 1) < 0.03 ? reference.singular : reference.plural
    }
}
