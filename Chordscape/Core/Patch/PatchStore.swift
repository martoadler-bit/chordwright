import Foundation

/// User-saved patches, persisted as one JSON file per patch in
/// Documents/Patches — same recipe as Modula's `PatchStore`.
enum PatchStore {
    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Patches", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ patch: Patch) {
        let url = directory.appendingPathComponent("\(patch.id).json")
        guard let data = try? JSONEncoder().encode(patch) else { return }
        try? data.write(to: url)
    }

    static func delete(_ patch: Patch) {
        let url = directory.appendingPathComponent("\(patch.id).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func loadAll() -> [Patch] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url -> Patch? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Patch.self, from: data)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
