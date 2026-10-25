import Foundation

/// Read-only compatibility with edits and preferences written by pre-rebrand development builds.
/// New files and Photos adjustment envelopes always use the iLightCraft identity.
nonisolated enum LegacyEditCompatibility {
    static let photosIdentifier = "com.cwallyman.UnveilNative.develop"
    static let engineVersion = "unveil-native-hdr-1"
    static let preferredLibraryKey = "UnveilPreferredLibrary"
    static func migratePreferences(_ defaults: UserDefaults = .standard) {
        let oldKey = preferredLibraryKey
        let newKey = "iLightCraftPreferredLibrary"
        if defaults.object(forKey: newKey) == nil, let value = defaults.string(forKey: oldKey) {
            defaults.set(value, forKey: newKey)
        }
    }
}
