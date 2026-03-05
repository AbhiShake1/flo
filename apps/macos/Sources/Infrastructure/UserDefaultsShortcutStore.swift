import AppCore
import Foundation

public final class UserDefaultsShortcutStore: ShortcutStore {
    private let defaults: UserDefaults
    private let key = "flo.shortcuts.bindings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadBindings() -> [ShortcutBinding] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ShortcutBinding].self, from: data)
        else {
            return DefaultShortcuts.all
        }

        var byAction = Dictionary(uniqueKeysWithValues: decoded.map { ($0.action, $0) })
        for required in DefaultShortcuts.all where byAction[required.action] == nil {
            byAction[required.action] = required
        }
        return ShortcutAction.allCases.compactMap { byAction[$0] }
    }

    public func saveBindings(_ bindings: [ShortcutBinding]) {
        guard let data = try? JSONEncoder().encode(bindings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
