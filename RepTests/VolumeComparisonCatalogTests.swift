import Testing
@testable import Rep

@Suite("Volume comparisons")
struct VolumeComparisonCatalogTests {
    @Test("Comparisons are produced for real session volumes")
    func comparisonsForTypicalVolume() {
        let items = VolumeComparisonCatalog.comparisons(forKilograms: 5_796, limit: 18)
        #expect(items.count == 18)
        #expect(items.contains { item in item.isSurprising })
        #expect(items.contains { item in !item.isSurprising })
        #expect(items.allSatisfy { item in !item.label.isEmpty && !item.detail.isEmpty })
    }

    @Test("Zero volume yields no comparisons")
    func zeroVolume() {
        let items = VolumeComparisonCatalog.comparisons(forKilograms: 0)
        #expect(items.isEmpty)
    }

    @Test("Near-exact piano match appears for 400 kg")
    func nearWholeFormatting() {
        let items = VolumeComparisonCatalog.comparisons(forKilograms: 400, limit: 24)
        let hasPiano = items.contains { item in item.detail.contains("piano") }
        #expect(hasPiano)
    }
}
