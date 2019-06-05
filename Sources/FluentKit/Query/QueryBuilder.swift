import NIO

//extension Database {
//    public func query<Model>(_ model: Model.Type) -> QueryBuilder<Model>
//        where Model: FluentKit.Model
//    {
//        return .init(database: self)
//    }
//}

public final class QueryBuilder<Model>
    where Model: FluentKit.Model
{
    public var query: DatabaseQuery

    internal let database: Database
    internal var eagerLoads: [String: EagerLoad]
    internal var includeSoftDeleted: Bool
    internal var joinedModels: [AnyModel]
    
    public init(database: Database) {
        self.database = database
        self.query = .init(entity: Model.entity)
        self.eagerLoads = [:]
        self.query.fields = Model.shared.all.map { .field(
            path: [$0.name],
            entity: Model.entity,
            alias: nil
        ) }
        self.includeSoftDeleted = false
        self.joinedModels = []
    }
    
    @discardableResult
    public func eagerLoad<Child>(_ key: Model.ChildrenKey<Child>, method: EagerLoadMethod = .subquery) -> Self
        where Child: FluentKit.Model
    {
        switch method {
        case .subquery:
            let children = Model.children(forKey: key)
            self.eagerLoads[Child.entity] = SubqueryChildEagerLoad<Model, Child>(children.id.name)
        case .join:
            fatalError()
        }
        return self
    }

    @discardableResult
    public func eagerLoad<Parent>(_ key: Model.ParentKey<Parent>, method: EagerLoadMethod = .subquery) -> Self
        where Parent: FluentKit.Model
    {
        let parent = Model.parent(forKey: key)
        switch method {
        case .subquery:
            self.eagerLoads[Parent.entity] = SubqueryParentEagerLoad<Model, Parent>(parent.id.name)
            return self
        case .join:
            self.eagerLoads[Parent.entity] = JoinParentEagerLoad<Model, Parent>()
            return self.join(key)
        }
    }
    
    @discardableResult
    public func join<Parent>(_ key: Model.ParentKey<Parent>) -> Self
        where Parent: FluentKit.Model
    {
        return self.join(
            Parent.self, Parent.shared.id.name,
            to: Model.self, Model.parent(forKey: key).id.name,
            method: .inner
        )
    }

    @discardableResult
    public func join<Foreign, Local, Value>(
        _ foreign: KeyPath<Foreign, Field<Value?>>,
        to local: KeyPath<Local, Field<Value>>,
        method: DatabaseQuery.Join.Method = .inner
    ) -> Self
        where Foreign: FluentKit.Model, Local: FluentKit.Model
    {
        return self.join(
            Foreign.self, Foreign.shared[keyPath: foreign].name,
            to: Local.self, Local.shared[keyPath: local].name,
            method: .inner
        )
    }

    @discardableResult
    public func join<Foreign, Local, Value>(
        _ foreign: KeyPath<Foreign, Field<Value>>,
        to local: KeyPath<Local, Field<Value?>>,
        method: DatabaseQuery.Join.Method = .inner
    ) -> Self
        where Foreign: FluentKit.Model, Local: FluentKit.Model
    {
        return self.join(
            Foreign.self, Foreign.shared[keyPath: foreign].name,
            to: Local.self, Local.shared[keyPath: local].name,
            method: .inner
        )
    }

    @discardableResult
    public func join<Foreign, Local, Value>(
        _ foreign: KeyPath<Foreign, Field<Value>>,
        to local: KeyPath<Local, Field<Value>>,
        method: DatabaseQuery.Join.Method = .inner
    ) -> Self
        where Foreign: FluentKit.Model, Local: FluentKit.Model
    {
        return self.join(
            Foreign.self, Foreign.shared[keyPath: foreign].name,
            to: Local.self, Local.shared[keyPath: local].name,
            method: .inner
        )
    }
    
    @discardableResult
    public func join<Foreign, Local>(
        _ foreign: Foreign.Type,
        _ foreignField: String,
        to local: Local.Type,
        _ localField: String,
        method: DatabaseQuery.Join.Method = .inner
    ) -> Self
        where Foreign: FluentKit.Model, Local: FluentKit.Model
    {
        self.query.fields += Foreign.shared.all.map {
            return .field(
                path: [$0.name],
                entity: Foreign.entity,
                alias: Foreign.entity + "_" + $0.name
            )
        }
        self.joinedModels.append(Foreign.shared)
        self.query.joins.append(.model(
            foreign: .field(path: [foreignField], entity: Foreign.entity, alias: nil),
            local: .field(path: [localField], entity: Local.entity, alias: nil),
            method: method
        ))
        return self
    }
    
    
    @discardableResult
    public func filter(_ filter: ModelFilter<Model>) -> Self {
        return self.filter(filter.filter)
    }
    
    @discardableResult
    public func filter<Value>(_ field: KeyPath<Model, Field<Value>>, in values: [Value]) -> Self {
        return self.filter(Model.shared[keyPath: field].name, in: values)
    }
    
    @discardableResult
    public func filter<Value>(_ fieldName: String, in values: [Value]) -> Self
        where Value: Codable
    {
        return self.filter(.field(path: [fieldName], entity: Model.entity, alias: nil), .subset(inverse: false), .array(values.map { .bind($0) })
        )
    }
    
    @discardableResult
    public func filter<Value>(_ field: KeyPath<Model, Field<Value>>, _ method: DatabaseQuery.Filter.Method, _ value: Value) -> Self {
        return self.filter(Model.shared[keyPath: field].name, method, value)
    }
    
    @discardableResult
    public func filter<Value>(_ fieldName: String, _ method: DatabaseQuery.Filter.Method, _ value: Value) -> Self
        where Value: Codable
    {
        return self.filter(.field(path: [fieldName], entity: Model.entity, alias: nil), method, .bind(value))
    }

    @discardableResult
    public func filter(_ field: DatabaseQuery.Field, _ method: DatabaseQuery.Filter.Method, _ value: DatabaseQuery.Value) -> Self {
        return self.filter(.basic(field, method, value))
    }
    
    @discardableResult
    public func filter(_ filter: DatabaseQuery.Filter) -> Self {
        self.query.filters.append(filter)
        return self
    }
    
    @discardableResult
    public func set(_ data: [String: DatabaseQuery.Value]) -> Self {
        query.fields = data.keys.map { .field(path: [$0], entity: nil, alias: nil) }
        query.input.append(.init(data.values))
        return self
    }
    
    @discardableResult
    public func set<Value>(_ field: KeyPath<Model, Field<Value>>, to value: Value) -> Self {
        self.query.fields = []
        query.fields.append(.field(path: [Model.shared[keyPath: field].name], entity: nil, alias: nil))
        switch query.input.count {
        case 0: query.input = [[.bind(value)]]
        default: query.input[0].append(.bind(value))
        }
        return self
    }
    
    // MARK: Actions
    
    public func create() -> EventLoopFuture<Void> {
        #warning("model id not set this way")
        self.query.action = .create
        return self.run()
    }
    
    public func update() -> EventLoopFuture<Void> {
        self.query.action = .update
        return self.run()
    }
    
    public func delete() -> EventLoopFuture<Void> {
        self.query.action = .delete
        return self.run()
    }
    
    
    // MARK: Aggregate
    
    public func count() -> EventLoopFuture<Int> {
        return self.aggregate(.count, \.id)
    }

    public func sum<Value>(_ key: KeyPath<Model, Field<Value?>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.sum, key)
    }
    
    public func sum<Value>(_ key: KeyPath<Model, Field<Value>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.sum, key)
    }

    public func average<Value>(_ key: KeyPath<Model, Field<Value?>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.average, key)
    }
    
    public func average<Value>(_ key: KeyPath<Model, Field<Value>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.average, key)
    }

    public func min<Value>(_ key: KeyPath<Model, Field<Value?>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.minimum, key)
    }
    
    public func min<Value>(_ key:KeyPath<Model, Field<Value>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.minimum, key)
    }

    public func max<Value>(_ key: KeyPath<Model, Field<Value?>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.maximum, key)
    }
    
    public func max<Value>(_ key: KeyPath<Model, Field<Value>>) -> EventLoopFuture<Value?>
        where Value: Codable
    {
        return self.aggregate(.maximum, key)
    }


    public func aggregate<Value, Result>(
        _ method: DatabaseQuery.Field.Aggregate.Method,
        _ field: KeyPath<Model, Field<Value>>,
        as type: Result.Type = Result.self
    ) -> EventLoopFuture<Result>
        where Result: Codable
    {
        return self.aggregate(method, Model.shared[keyPath: field].name, as: Result.self)
    }
    
    public func aggregate<Result>(
        _ method: DatabaseQuery.Field.Aggregate.Method,
        _ fieldName: String,
        as type: Result.Type = Result.self
    ) -> EventLoopFuture<Result>
        where Result: Codable
    {
        self.query.fields = [.aggregate(.fields(
            method: method,
            fields: [.field(path: [fieldName], entity: Model.entity, alias: nil)]
        ))]
        
        return self.first().flatMapThrowing { res in
            guard let res = res else {
                fatalError("No model")
            }
            return try res.storage.output!.decode(field: "fluentAggregate", as: Result.self)
        }
    }
    
    public enum EagerLoadMethod {
        case subquery
        case join
    }
    
    
    // MARK: Fetch
    
    public func chunk(max: Int, closure: @escaping ([Row<Model>]) throws -> ()) -> EventLoopFuture<Void> {
        var partial: [Row<Model>] = []
        partial.reserveCapacity(max)
        return self.run { row in
            partial.append(row)
            if partial.count >= max {
                try closure(partial)
                partial = []
            }
        }.flatMapThrowing { 
            // any stragglers
            if !partial.isEmpty {
                try closure(partial)
                partial = []
            }
        }
    }
    
    public func first() -> EventLoopFuture<Row<Model>?> {
        return all().map { $0.first }
    }
    
    public func all() -> EventLoopFuture<[Row<Model>]> {
        #warning("re-use array required by run for eager loading")
        var models: [Row<Model>] = []
        return self.run { model in
            models.append(model)
        }.map { models }
    }

    internal func action(_ action: DatabaseQuery.Action) -> Self {
        self.query.action = action
        return self
    }
    
    public func run() -> EventLoopFuture<Void> {
        return self.run { _ in }
    }
    
    public func run(_ onOutput: @escaping (Row<Model>) throws -> ()) -> EventLoopFuture<Void> {
        var all: [Row<Model>] = []
        
        // make a copy of this query before mutating it
        // so that run can be called multiple times
        var query = self.query

        // check if model is soft-deletable and should be excluded
        if let softDeletable = Model.shared as? _AnySoftDeletable, !self.includeSoftDeleted {
            softDeletable._excludeSoftDeleted(&query)
            self.joinedModels
                .compactMap { $0 as? _AnySoftDeletable }
                .forEach { $0._excludeSoftDeleted(&query) }
        }

        return self.database.execute(query) { output in
            let model = try Row<Model>(storage: DefaultModelStorage(
                output: output,
                eagerLoads: self.eagerLoads,
                exists: true
            ))
            all.append(model)
            try onOutput(model)
        }.flatMap {
            return .andAllSucceed(self.eagerLoads.values.map { eagerLoad in
                return eagerLoad.run(all, on: self.database)
            }, on: self.database.eventLoop)
        }
    }
}

public struct ModelFilter<Model> where Model: FluentKit.Model {
    static func make<Value>(_ lhs: KeyPath<Model, Field<Value>>, _ method: DatabaseQuery.Filter.Method, _ rhs: Value) -> ModelFilter {
        return .init(filter: .basic(
            .field(path: [Model.shared[keyPath: lhs].name], entity: Model.entity, alias: nil),
            method,
            .bind(rhs)
        ))
    }
    
    let filter: DatabaseQuery.Filter
    init(filter: DatabaseQuery.Filter) {
        self.filter = filter
    }
}

public func ==<Model, Value>(lhs: KeyPath<Model, Field<Value>>, rhs: Value) -> ModelFilter<Model>
    where Model: FluentKit.Model
{
    return .make(lhs, .equality(inverse: false), rhs)
}
