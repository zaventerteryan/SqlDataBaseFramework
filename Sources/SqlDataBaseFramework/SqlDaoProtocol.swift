//
//  SqlDaoProtocol.swift
//  PizzeriaManager
//
//  Created by Zaven Terteryan on 6/26/25.
//

protocol SqlDaoProtocol {
    func createTable(db: OpaquePointer?)
    func getNextDbId() -> Int64
    func insert(object: SqlObject)
    func get(dbId: Int64) -> SqlObject?
    func delete(object: SqlObject)
    func migrateTableIfNeeded(db: OpaquePointer?)
}
