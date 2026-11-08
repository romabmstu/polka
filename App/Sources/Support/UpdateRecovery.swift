import Foundation
import PolkaSystem

/// Remembers a build that crashed right after an update and was rolled back,
/// so automatic checks don't install it again.
enum UpdateRecovery {
    private static let skippedKey = "skippedUpdateBuild"

    /// The build that crashed, if this launch follows a rollback. Reading it
    /// moves it to the skipped builds, so it is reported once.
    static func takeRolledBackBuild(defaults: UserDefaults = .standard) -> Int? {
        let build = defaults.integer(forKey: Updater.rolledBackBuildKey)
        guard build > 0 else { return nil }
        defaults.removeObject(forKey: Updater.rolledBackBuildKey)
        defaults.set(max(build, defaults.integer(forKey: skippedKey)), forKey: skippedKey)
        return build
    }

    /// Automatic checks pass over builds up to this one.
    static func skippedBuild(defaults: UserDefaults = .standard) -> Int? {
        let build = defaults.integer(forKey: skippedKey)
        return build > 0 ? build : nil
    }
}
