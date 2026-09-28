import Foundation

struct ProjectDisplayPreferences {
    enum Key: String, CaseIterable {
        case columns, sortColumn, sortAscending, fieldID, groupsByStatus, cardFields
        case roadmapStartField, roadmapEndField, roadmapZoom, roadmapGroupsByStatus, roadmapTitleWidth
    }

    let id: String

    init(id: String) {
        self.id = id
    }

    init(projectID: String, viewID: String?) {
        id = viewID.map { "\(projectID).view.\($0)" } ?? projectID
    }

    func key(for key: Key) -> String {
        "projectTable.\(id).\(key.rawValue)"
    }

    /// An absent preference uses the default; an explicit empty value means None.
    static func roadmapFieldID(_ storedID: String?, defaultName: String, fields: [ProjectField]) -> String {
        guard let storedID else {
            return (try? ProjectField.dateField(named: defaultName, in: fields))?.id ?? ""
        }
        return fields.contains { $0.id == storedID && ($0.kind == .date || $0.kind == .iteration) }
            ? storedID : ""
    }

    func copy(to destination: Self, defaults: UserDefaults = .standard) {
        for key in Key.allCases {
            defaults.set(defaults.object(forKey: self.key(for: key)), forKey: destination.key(for: key))
        }
    }

    func remove(defaults: UserDefaults = .standard) {
        for key in Key.allCases {
            defaults.removeObject(forKey: self.key(for: key))
        }
    }
}
