import SwiftData
import Foundation

enum TypaSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [TypingResult.self]
    }
}

enum TypaSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TypaSchemaV1.self]
    }
    
    static var stages: [MigrationStage] {
        []
    }
}
