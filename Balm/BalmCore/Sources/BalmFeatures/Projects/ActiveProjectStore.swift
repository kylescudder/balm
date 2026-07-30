import Foundation
import Observation
import BalmModels

/// Persisted reference to the project the user works in by default. Stored in
/// UserDefaults so it survives relaunch. Sign-out clears the cached value.
@MainActor
@Observable
public final class ActiveProjectStore {
    public private(set) var project: JiraProject?

    public init() {
        self.project = Self.load()
    }

    public func set(_ project: JiraProject?) {
        self.project = project
        if let project {
            Self.save(project)
        } else {
            Self.clear()
        }
    }

    private static let key = "activeProject.bundle.v1"

    private static func load() -> JiraProject? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(JiraProject.self, from: data)
    }

    private static func save(_ project: JiraProject) {
        if let data = try? JSONEncoder().encode(project) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
