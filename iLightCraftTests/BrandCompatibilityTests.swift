import Foundation
import Testing
@testable import iLightCraft

/// Saved for manual execution; no personal media or app launch required.
struct BrandCompatibilityTests {
    @Test func currentAndLegacyPhotosEditsRemainReadable() throws {
        let settings = Data(#"{"version":1}"#.utf8)
        let current = try PhotosAdjustment(settings: settings, rawDecoderVersion: nil)
        #expect(current.engine == "ilightcraft-native-hdr-1")
        #expect(PhotosAdjustment.identifier == "com.cwallyman.iLightCraft.develop")
        #expect(PhotosAdjustment.canRead(LegacyEditCompatibility.photosIdentifier))
        #expect(!PhotosAdjustment.canRead("another.editor"))
        let legacy: [String: Any] = ["schema": 1, "engine": LegacyEditCompatibility.engineVersion, "settings": settings.base64EncodedString()]
        let restored = try PhotosAdjustment.decode(JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.settings == settings)
    }
    @Test func preferenceMigrationPreservesAnExistingChoice() throws {
        let suite = "BrandMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("photos", forKey: LegacyEditCompatibility.preferredLibraryKey)
        LegacyEditCompatibility.migratePreferences(defaults)
        #expect(defaults.string(forKey: "iLightCraftPreferredLibrary") == "photos")
        defaults.set("files", forKey: "iLightCraftPreferredLibrary")
        LegacyEditCompatibility.migratePreferences(defaults)
        #expect(defaults.string(forKey: "iLightCraftPreferredLibrary") == "files")
    }
}
