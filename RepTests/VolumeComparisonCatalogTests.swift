import Testing
@testable import Rep

@Suite("Volume comparisons")
struct VolumeComparisonCatalogTests {
    @Test("Typical volume yields one impressive and one fun comparison")
    func comparisonsForTypicalVolume() {
        let items = VolumeComparisonCatalog.comparisons(forKilograms: 5_796)
        #expect(items.count == 2)
        #expect(items.contains { item in item.isSurprising })
        #expect(items.contains { item in !item.isSurprising })
        #expect(items.allSatisfy { item in !item.label.isEmpty && !item.detail.isEmpty })
    }

    @Test("Zero volume yields no comparisons")
    func zeroVolume() {
        let items = VolumeComparisonCatalog.comparisons(forKilograms: 0)
        #expect(items.isEmpty)
    }

    @Test("Near-exact piano volume can surface as the impressive pick")
    func nearWholeFormatting() {
        let items = VolumeComparisonCatalog.comparisons(forKilograms: 400)
        #expect(items.contains { !$0.isSurprising })
        #expect(items.count <= 2)
    }
}
