public struct RowParent<Value>
    where Value: Model
{
    let parentID: String
    let childID: String
    var storage: Storage

    public var id: Value.ID {
        get {
            return self.storage.get(self.childID)
        }
        set {
            self.storage.set(self.childID, to: newValue)
        }
    }

    public func eagerLoaded() throws -> Row<Value> {
        guard let cache = self.storage.eagerLoads[Value.entity] else {
            throw FluentError.missingEagerLoad(name: Value.entity.self)
        }
        return try cache.get(id: self.storage.get(self.childID, as: Value.ID.self))
            .map { $0 as! Row<Value> }
            .first!
    }

    public func query(on database: Database) -> QueryBuilder<Value> {
        return Value.query(on: database)
            .filter(self.parentID, .equal, self.storage.get(self.childID, as: Value.ID.self))
    }


    public func get(on database: Database) -> EventLoopFuture<Row<Value>> {
        return self.query(on: database).first().map { parent in
            guard let parent = parent else {
                fatalError()
            }
            return parent
        }
    }
}