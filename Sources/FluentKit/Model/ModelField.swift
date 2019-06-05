public enum ModelError: Error {
    case missingField(name: String)
}

public struct Field<Value>: ModelProperty
    where Value: Codable
{
    public var type: Any.Type {
        return Value.self
    }
    
    public var constraints: [DatabaseSchema.FieldConstraint]
    
    public let name: String
    
//    public var path: [String] {
//        return self.model.storage.path + [self.name]
//    }

    internal let dataType: DatabaseSchema.DataType?

    #warning("TODO: auto migrate")
    struct Interface: Codable {
        let name: String
    }
    
    public init(
        _ name: String,
        dataType: DatabaseSchema.DataType? = nil,
        constraints: DatabaseSchema.FieldConstraint...
    ) {
        self.name = name
        self.dataType = dataType
        self.constraints = constraints
    }

    func cached(from output: DatabaseOutput) throws -> Any? {
        guard output.contains(field: self.name) else {
            return nil
        }
        return try output.decode(field: self.name, as: Value.self)
    }
    
    func encode(to encoder: inout ModelEncoder, from storage: ModelStorage) throws {
        try encoder.encode(storage.get(self.name, as: Value.self), forKey: self.name)
    }

    func decode(from decoder: ModelDecoder, to storage: inout ModelStorage) throws {
        try storage.set(self.name, to: decoder.decode(Value.self, forKey: self.name))
    }
}

extension Field: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

//extension Model {
//    public func field<Value>(
//        _ name: String,
//        _ dataType: DatabaseSchema.DataType? = nil,
//        _ constraints: DatabaseSchema.FieldConstraint...
//    ) -> Field<Value>
//        where Value: Codable
//    {
//        return .init(name: name, dataType: dataType, constraints: constraints)
//    }
//
//    public func id<Value>(
//        _ name: String,
//        _ dataType: DatabaseSchema.DataType? = nil,
//        _ constraints: DatabaseSchema.FieldConstraint...
//    ) -> Field<Value>
//        where Value: Codable
//    {
//        return .init(
//            model: self,
//            name: name,
//            dataType: dataType,
//            constraints: constraints + [.identifier]
//        )
//    }
//}
