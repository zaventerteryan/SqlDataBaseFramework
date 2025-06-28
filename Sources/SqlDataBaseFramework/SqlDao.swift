//
//  SqlDao.swift
//  Project
//
//  Created by Zaven Terteryan on 9/2/24.
//  Copyright © 2024 Zangi Livecom Pte. Ltd. All rights reserved.
//

import Foundation
import SQLite3

private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private let primaryKeyName: String = "dbId"

class SqlDao<B: SqlObjectProtocol>: NSObject, SqlDaoProtocol {
    private let serialQueue = DispatchQueue(label: "SqlDao")
    var isLog: Bool = false
    private var nextDbId: Int64 = -1
    
    var storePath: String {
        return SqlConnector.sharedInstance.storePath
    }
    
    func createTable(db: OpaquePointer?) {
        var cursor: OpaquePointer? = nil
        let className = String(describing: B.self)
        var query = "CREATE TABLE IF NOT EXISTS \(className)(\(primaryKeyName) INTEGER PRIMARY KEY NOT NULL"
    
        let properties = Self.getProperties(B.self as? AnyClass)

        for property in properties  {
            if (property.propertyName == primaryKeyName){
                continue
            }
            
            query += ", \(property.propertyName) \(property.getSqlType())"
        }
        
        query += ");"
        
        if sqlite3_prepare_v2(db, query, -1, &cursor, nil) == SQLITE_OK {
            if sqlite3_step(cursor) == SQLITE_DONE {
                print("\(className) table created.")
            } else {
                print("\(className) table could not be created.")
            }
        } else {
            let char = sqlite3_errmsg(db)
            if (char != nil){
                print("CREATE TABLE statement could not be prepared. \(String(cString: char!))")
            } else {
                print("CREATE TABLE statement could not be prepared.")
            }
        }
        
        sqlite3_finalize(cursor)
    }
    
    func migrateTableIfNeeded(db: OpaquePointer?) {
        self.addColumsIfNeeded(db: db)
        self.deleteColumsIfNeeded(db: db)
    }
    
    func addColumsIfNeeded(db: OpaquePointer?) {
        let className = String(describing: B.self)
        var existingColumns: Set<String> = []
        var pragmaCursor: OpaquePointer? = nil
        let pragmaQuery = "PRAGMA table_info(\(className));"

        if sqlite3_prepare_v2(db, pragmaQuery, -1, &pragmaCursor, nil) == SQLITE_OK {
            while sqlite3_step(pragmaCursor) == SQLITE_ROW {
                if let columnNameCStr = sqlite3_column_text(pragmaCursor, 1) {
                    let columnName = String(cString: columnNameCStr)
                    existingColumns.insert(columnName)
                }
            }
        }
        sqlite3_finalize(pragmaCursor)

        let properties = Self.getProperties(B.self as? AnyClass)
        for property in properties {
            let columnName = property.propertyName
            if columnName == primaryKeyName {
                continue
            }

            if !existingColumns.contains(columnName) {
                let alterQuery = "ALTER TABLE \(className) ADD COLUMN \(columnName) \(property.getSqlType());"
                var alterCursor: OpaquePointer? = nil
                if sqlite3_prepare_v2(db, alterQuery, -1, &alterCursor, nil) == SQLITE_OK {
                    if sqlite3_step(alterCursor) == SQLITE_DONE {
                        print("Added column \(columnName) to \(className) table.")
                    } else {
                        print("Failed to add column \(columnName) to \(className) table.")
                    }
                } else {
                    if let errorMsg = sqlite3_errmsg(db) {
                        print("ALTER TABLE failed: \(String(cString: errorMsg))")
                    }
                }
                sqlite3_finalize(alterCursor)
            }
        }
    }
    
    func deleteColumsIfNeeded(db: OpaquePointer?) {
        let className = String(describing: B.self)

        var existingColumns: Set<String> = []
        var pragmaCursor: OpaquePointer? = nil
        let pragmaQuery = "PRAGMA table_info(\(className));"

        if sqlite3_prepare_v2(db, pragmaQuery, -1, &pragmaCursor, nil) == SQLITE_OK {
            while sqlite3_step(pragmaCursor) == SQLITE_ROW {
                if let columnNameCStr = sqlite3_column_text(pragmaCursor, 1) {
                    let columnName = String(cString: columnNameCStr)
                    existingColumns.insert(columnName)
                }
            }
        }
        sqlite3_finalize(pragmaCursor)

        let properties = Self.getProperties(B.self as? AnyClass)
        let modelColumns = Set(properties.map { $0.propertyName })
        let extraColumns = existingColumns.subtracting(modelColumns)

        guard !extraColumns.isEmpty else {
            return
        }

        // 4. Rebuild the table
        let tempTable = "\(className)_temp"
        let allColumnsToKeep = existingColumns.subtracting(extraColumns).filter { $0 != primaryKeyName }

        // a) Create temp table
        var createQuery = "CREATE TABLE \(tempTable) (\(primaryKeyName) INTEGER PRIMARY KEY NOT NULL"
        for property in properties {
            if property.propertyName == primaryKeyName { continue }
            if allColumnsToKeep.contains(property.propertyName) {
                createQuery += ", \(property.propertyName) \(property.getSqlType())"
            }
        }
        createQuery += ");"

        if sqlite3_exec(db, createQuery, nil, nil, nil) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("CREATE TEMP TABLE failed: \(errorMsg)")
            return
        }

        // b) Copy data
        let copyColumns = [primaryKeyName] + allColumnsToKeep
        let columnList = copyColumns.joined(separator: ", ")
        let copyQuery = "INSERT INTO \(tempTable) (\(columnList)) SELECT \(columnList) FROM \(className);"

        if sqlite3_exec(db, copyQuery, nil, nil, nil) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("COPY DATA failed: \(errorMsg)")
            return
        }

        // c) Drop old table
        if sqlite3_exec(db, "DROP TABLE \(className);", nil, nil, nil) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("DROP OLD TABLE failed: \(errorMsg)")
            return
        }

        // d) Rename temp table
        if sqlite3_exec(db, "ALTER TABLE \(tempTable) RENAME TO \(className);", nil, nil, nil) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            print("RENAME TABLE failed: \(errorMsg)")
            return
        }

        print("\(className) table rebuilt to remove extra columns.")
    }
    
    func insert(object: SqlObject) {
        var obj: SqlObject? = object
        
        let oldObj = self.get(filter: "dbId == \(object.dbId)")
        
        if oldObj.count > 0 {
            obj!.dbId = oldObj[0].dbId
            serialQueue.sync {
                SqlDao.update(object: obj!, db: SqlConnector.sharedInstance.db)
            }
        } else {
            serialQueue.sync {
                SqlDao.insert(object: &obj!, db: SqlConnector.sharedInstance.db)
            }
        }
    }
    
    private static func insert<T: SqlObjectProtocol>(object: inout T, db: OpaquePointer?) {
        var cursor: OpaquePointer? = nil
        
        var insertStatementString = "INSERT INTO \(String(describing: object.getType())) ("
        
        
        var properties = self.getProperties(object.getType())
        let primarykey = SqlPropertyHolder(propertyName: primaryKeyName, propertyType: "Int")
        properties.append(primarykey)
        var propertiesToInsert: [SqlObject] = []
        var count = 0
        var columnList = ""
    
        for property in properties {
            count += 1
            columnList += "\(property.propertyName), "
        }
        
        columnList = String(columnList.dropLast(2))
        
        insertStatementString += "\(columnList)) VALUES ("
        
        for i in 0..<count {
            insertStatementString += "?"
            if i != count - 1 {
                insertStatementString += ", "
            }
        }
        
        insertStatementString += ");"
        let cachKey = "\(object.dbId)\(object.getType())"
        SqlCache.sharedInstance.objs[cachKey] = [object] as? SqlObject
        if sqlite3_prepare_v2(db, insertStatementString, -1, &cursor, nil) == SQLITE_OK {
            
            var position: Int32 =  1
            for property in properties {
                let propertyValue = (object as! NSObject).value(forKey: property.propertyName)
                
                if (propertyValue is SqlObject){
                    propertiesToInsert.append(propertyValue as! SqlObject)
                } else if (propertyValue is Array<Any>){
                    for valueArray in (propertyValue as? Array<Any>) ?? [] {
                        if (valueArray is SqlObject) {
                            propertiesToInsert.append(valueArray as! SqlObject)
                        }
                    }
                }
                
                    
                if (!self.store(db: db, cursor: cursor, position: position, value: propertyValue)){
                    sqlite3_finalize(cursor)
                    return
                }
                
                position += 1
            }
            
            guard sqlite3_step(cursor) == SQLITE_DONE else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                print("_insert sqlite3_step -> Details: \(errMsg)")
                sqlite3_finalize(cursor)
                Thread.sleep(forTimeInterval: 0.05)
                self.insert(object: &object, db: db)
                return
            }
        } else {
            print("INSERT statement could not be prepared.")
        }
        
        object.dbId = sqlite3_last_insert_rowid(db)
        sqlite3_finalize(cursor)
        
        for obj in propertiesToInsert {
            let dao = SqlConnector.sharedInstance.getDao(obj: obj)
            dao.insert(object: obj)
        }
    }
    
    open func update(object: B) {
        serialQueue.sync {
            SqlDao.update(object: object, db: SqlConnector.sharedInstance.db)
        }
    }
    
    private static func update<T: SqlObjectProtocol>(object: T, db: OpaquePointer?){
        if db == nil {
            print("Unable to open database. Verify that you created the directory described " +
                "in the Getting Started section.")
            return
        }
        
        let properties = self.getProperties(object.getType())
        var query = "UPDATE \(String(describing: object.getType())) SET"
        
        for property in properties {
            if (property.propertyName == primaryKeyName){
                continue
            }
                
            query += " \(property.propertyName) = ?,"
        }
        
        query = String(query.dropLast())
        query += " WHERE \(primaryKeyName) == \(object.dbId)"
        
        var cursor: OpaquePointer? = nil
        let cachKey = "\(object.dbId)\(object.getType())"
        SqlCache.sharedInstance.objs[cachKey] = [object] as? SqlObject
        guard sqlite3_prepare_v2(db, query, -1, &cursor, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("_update sqlite3_prepare_v2 -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return
        }
        
        var position: Int32 = 1
        for property in properties {
            if (property.propertyName == primaryKeyName){
                continue
            }
                
            let propertyValue = (object as! NSObject).value(forKey: property.propertyName)
                
            if (!self.store(db: db, cursor: cursor, position: position, value: propertyValue)){
                sqlite3_finalize(cursor)
                return
            }
            
            position += 1
        }
        
        guard sqlite3_step(cursor) == SQLITE_DONE else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("_update sqlite3_step -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            Thread.sleep(forTimeInterval: 0.05)
            self.update(object: object, db: db)
            return
        }
        
        guard sqlite3_changes(db) > 0 else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("_update sqlite3_changes -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return
        }
        
        sqlite3_finalize(cursor)
    }
    
    open func get(filter: String) -> [B] {
        var arr: [B] = []
        serialQueue.sync {
            arr = SqlDao.get(filter: filter)
        }
        
        return arr
    }
    
    func get(dbId: Int64) -> SqlObject? {
        let cachKey = "\(dbId)\(String(describing: B.self))"
        let cacheObject = SqlCache.sharedInstance.objs[cachKey]
        if cacheObject != nil {
            return cacheObject
        }
        
        return self.getConvert(dbId: dbId) as? SqlObject
    }
    
    private func getConvert(dbId: Int64) -> B? {
        return SqlDao.get(filter: "\(primaryKeyName) == \(dbId)").first
    }
    
    static func get<T: SqlObjectProtocol>(filter: String) -> [T] {
        var changedFilter = filter.replacingOccurrences(of: "&&", with: "AND")
        changedFilter = changedFilter.replacingOccurrences(of: "||", with: "OR")
        
        var query = "SELECT \(primaryKeyName),"
        
        let properties = self.getProperties(T.self as? AnyClass)
        for property in properties {
            if (property.propertyName == primaryKeyName){
                continue
            }
            
            query += " \(property.propertyName),"
        }
        
        query = String(query.dropLast())
        query += " FROM \(String(describing: T.self))"
        
        if (changedFilter != ""){
            query += " WHERE \(changedFilter)"
        }
        query += ";"
        
        return self.get(query)
    }
    
    private static func get<T: SqlObjectProtocol>(_ query: String) -> [T] {
        var dbObjects: [T] = []
        if SqlConnector.sharedInstance.db == nil {
            print("Unable to open database. Verify that you created the directory described " +
                  "in the Getting Started section.")
            return dbObjects
        }
        
        var cursor: OpaquePointer? = nil
        let result = sqlite3_prepare_v2(SqlConnector.sharedInstance.db, query, -1, &cursor, nil)
        if  result == SQLITE_OK {
            if let createdIns = self.createInstance(className: String(describing: T.self)) {
                while sqlite3_step(cursor) == SQLITE_ROW{
                    if let value = self.createObject(cursor: cursor!, classObject: createdIns) {
                        dbObjects.append(value as! T)
                    }
                }
            }
        } else {
            let errMsg = String(cString: sqlite3_errmsg(SqlConnector.sharedInstance.db))
            print("-> Details: \(errMsg)")
            print("SELECT statement could not be prepared")
        }
        
        
        sqlite3_finalize(cursor)
        return dbObjects
    }
    
    private static func createObject(cursor: OpaquePointer, classObject: SqlObjectProtocol) -> SqlObject? {
        if let classType = NSClassFromString(String(describing: classObject.getType())) as? SqlObject.Type {
            var obj = classType.init()
            
            let properties = self.getProperties(classObject.getType())
            var position: Int32 = 0
            
            obj.dbId = sqlite3_column_int64(cursor, position)
            let cachKey = "\(obj.dbId)\(classType)"
            let oldObj = SqlCache.sharedInstance.objs[cachKey]
            if oldObj != nil {
                obj = oldObj!
            } else {
                SqlCache.sharedInstance.objs[cachKey] = obj
            }
            
            position += 1
            
            for property in properties {
                if (property.propertyName == primaryKeyName || oldObj != nil){
                    continue
                }
                
                if property.propertyType != "" {
                    if property.propertyType.hasPrefix("q") {
                        obj.setValue(sqlite3_column_int64(cursor, position), forKey: property.propertyName)
                    } else if property.propertyType.hasPrefix("f") || property.propertyType.hasPrefix("d") {
                        obj.setValue(sqlite3_column_double(cursor, position), forKey: property.propertyName)
                    } else if property.propertyType.hasPrefix("i") {
                        obj.setValue(sqlite3_column_int(cursor, position), forKey: property.propertyName)
                    } else if property.propertyType.contains("Array") {
                        var arr: [Any] = []
                        let value = sqlite3_column_text(cursor, position)
                        if let stringValue = value {
                            arr = SqlWrapper.tryToConvertFromArray(json: stringValue)
                        }
                        
                        obj.setValue(arr, forKey: property.propertyName)
                    } else if property.propertyType.hasPrefix("@") {
                        let value = sqlite3_column_text(cursor, position)
                        
                        if (value != nil){
                            let jsonString = String(cString: value!)
                            if let data = jsonString.data(using: .utf8) {
                                let decoder = JSONDecoder()
                                decoder.dateDecodingStrategy = .iso8601
                                if let wrapper = try? decoder.decode(SqlWrapper.self, from: data) {
                                    obj.setValue(wrapper.toSqlObject(), forKey: property.propertyName)
                                } else {
                                    obj.setValue(String(cString: sqlite3_column_text(cursor, position)), forKey: property.propertyName)
                                }
                            } else {
                                obj.setValue(String(cString: sqlite3_column_text(cursor, position)), forKey: property.propertyName)
                            }
                        } else {
                            obj.setValue(nil, forKey: property.propertyName)
                        }
                        
                    } else if property.propertyType.hasPrefix("B") || property.propertyType.hasPrefix("c") {
                        obj.setValue(sqlite3_column_int(cursor, position) == 1, forKey: property.propertyName)
                    }
                }
                
                position += 1
            }
            
            return obj
        }
        
        return nil
    }
    
    static func createInstance(className: String) -> SqlObjectProtocol? {
        guard let classType = NSClassFromString(className) as? NSObject.Type else {
            print("Error: Unable to get the class type from the class name.")
            return nil
        }

        return classType.init() as? SqlObjectProtocol
    }
    
    static func prepareDb(db: OpaquePointer?, query: String) -> OpaquePointer? {
        var cursor: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, query, -1, &cursor, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("prepareDb sqlite3_prepare_v2              -> Details: \(errMsg)")
            return nil
        }
        
        return cursor
    }
    
    static func save(db: OpaquePointer?, cursor: OpaquePointer?){
        guard sqlite3_step(cursor) == SQLITE_DONE else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("save sqlite3_step                -> Details: \(errMsg)")
            return
        }
        
        guard sqlite3_changes(db) > 0 else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("save sqlite3_changes                -> Details: \(errMsg)")
            return
        }
    }
    
    static func errorHandling(db: OpaquePointer?) -> Bool{
        let errMsg = String(cString: sqlite3_errmsg(db))
        if errMsg == "not an error" {
            return false
        }
        print("EC -> _insert sqlite3_bind_blob               -> Details: \(errMsg)")
        return true
    }
    
    static func store(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: Any?) -> Bool {
        if (value is SqlObject){
            return self.saveDBObject(db: db, cursor: cursor, position: position, value: value as? SqlObject)
        } else if (value is Array<Any>){
            return self.saveArray(db: db, cursor: cursor, position: position, value: value as? Array<Any>)
        } else if (value is String){
            return self.saveString(db: db, cursor: cursor, position: position, value: value as? String)
        } else if (value is Int32){
            return self.saveInt(db: db, cursor: cursor, position: position, value: value as? Int)
        } else if (value is Int64){
            return self.saveInt64(db: db, cursor: cursor, position: position, value: value as? Int64)
        } else if (value is Bool){
            return self.saveBool(db: db, cursor: cursor, position: position, value: value as? Bool)
        } else if (value is Double){
            return self.saveDouble(db: db, cursor: cursor, position: position, value: value as? Double)
        } else {
            return self.saveNil(db: db, cursor: cursor, position: position)
        }
    }
    
    static func saveDBObject(db generalDB: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: SqlObject?) -> Bool {
        let jsonEncoder = JSONEncoder()
        do {
            let jsonData = try jsonEncoder.encode(SqlWrapper(obj: value!))
            let jsonString = String(data: jsonData, encoding: .utf8)
            return self.saveString(db: generalDB, cursor: cursor, position: position, value: jsonString)
        } catch {
            return self.saveNil(db: generalDB, cursor: cursor, position: position)
        }
    }
    
    static func saveArray(db generalDB: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: Array<Any>?) -> Bool {
        if (value == nil){
            return self.saveNil(db: generalDB, cursor: cursor, position: position)
        }
        
        var arr: [SqlWrapper] = []
        for obj in value! {
            let wrapper = SqlWrapper(obj: obj)
            arr.append(wrapper)
        }
        
        let jsonEncoder = JSONEncoder()
        do {
            let jsonData = try jsonEncoder.encode(arr)
            let jsonString = String(data: jsonData, encoding: .utf8)
            return self.saveString(db: generalDB, cursor: cursor, position: position, value: jsonString)
        } catch {
            return false
        }
    }
    
    static func saveString(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: String?) -> Bool {
        guard sqlite3_bind_text(cursor, position, value, -1, TRANSIENT) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("EC -> SecurityDao _insert sqlite3_prepare_v2               -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return false
        }
        
        return true
    }
    
    static func saveArray(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: Array<SqlWrapper>) -> Bool {
        let encoder = JSONEncoder()
        if let encodedArray = try? encoder.encode(value) {
            let encodedArrayCString = encodedArray.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> UnsafePointer<Int8> in
                return pointer.bindMemory(to: Int8.self).baseAddress!
            }
            
            guard sqlite3_bind_text(cursor, position, encodedArrayCString, -1, TRANSIENT) == SQLITE_OK else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                print("EC -> SecurityDao _insert sqlite3_prepare_v2               -> Details: \(errMsg)")
                sqlite3_finalize(cursor)
                return false
            }
            
            return true
        } else {
            return false
        }
    }
    
    static func saveBool(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: Bool?) -> Bool {
        guard sqlite3_bind_int(cursor, position, (value ?? false) ? 1 : 0) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("_insert sqlite3_bind_int64 -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return false
        }
        
        return true
    }
    
    static func saveInt(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: Int?) -> Bool {
        guard sqlite3_bind_int(cursor, position, Int32(value ?? -1)) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("_insert sqlite3_bind_int64 -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return false
        }
        
        return true
    }
    
    static func saveDouble(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: Double?) -> Bool {
        guard sqlite3_bind_double(cursor, position, value ?? -1) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("_insert sqlite3_bind_int64 -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return false
        }
        
        return true
    }
    
    static func saveInt64(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32, value: Int64?) -> Bool {
        guard sqlite3_bind_int64(cursor, position, value ?? -1) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("_insert sqlite3_bind_int64 -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return false
        }
        
        return true
    }
    
    static func saveNil(db: OpaquePointer?, cursor: OpaquePointer?, position: Int32) -> Bool {
        guard sqlite3_bind_null(cursor, position) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("EC -> SecurityDao _insert sqlite3_prepare_v2 -> Details: \(errMsg)")
            sqlite3_finalize(cursor)
            return false
        }
        
        return true
    }
    
    func delete(object: SqlObject){
        self.delete(object: object as! B)
    }
    
    open func delete(object: B) {
        serialQueue.sync {
            SqlDao.delete(object: object)
        }
    }
    
    static func delete<T: SqlObjectProtocol>(object: T) {
        if SqlConnector.sharedInstance.db == nil {
            print("Unable to open database. Verify that you created the directory described " +
                  "in the Getting Started section.")
            return
        }
        var cursor: OpaquePointer? = nil
        
        let query = "DELETE FROM \(String(describing: T.self)) WHERE \(primaryKeyName) == \(object.dbId);"
        let cachKey = "\(object.dbId)\(object.getType())"
        SqlCache.sharedInstance.objs.removeValue(forKey: cachKey)
        if sqlite3_prepare_v2(SqlConnector.sharedInstance.db, query, -1, &cursor, nil) == SQLITE_OK {
            if sqlite3_step(cursor) == SQLITE_DONE {
                //                    print("Successfully deleted row with key \(part.key)")
            } else {
                print("Could not delete row with key \(object.dbId)")
            }
        } else {
            print("DELETE statement could not be prepared with key \(object.dbId)")
        }
        
        sqlite3_finalize(cursor)
        
    }
    
    func getProperties() -> [SqlPropertyHolder] {
        return Self.getProperties(B.self as? AnyClass)
    }
    
    private static func getProperties(_ objClass: AnyClass?) -> [SqlPropertyHolder] {
        guard let objectClass = objClass else {
            return []
        }
        
        let className = String(describing: objectClass.self)
        var holders: [SqlPropertyHolder]? = SqlCache.sharedInstance.properties[className]
        if holders == nil {
            var outCount: UInt32 = 0
            let properties = class_copyPropertyList(objectClass, &outCount)
            holders = []
            for i in 0..<Int(outCount) {
                let property = properties![i]
                let name = property_getName(property)
                let propertyName = String(cString: name)
                var propertyType = ""
                if let type = property_copyAttributeValue(property, "T") {
                    propertyType = String(cString: type)
                    free(type)
                }
                
                let holder = SqlPropertyHolder(propertyName: propertyName, propertyType: propertyType)
                holders!.append(holder)
            }
            
            SqlCache.sharedInstance.properties[className] = holders
        }
        
        return holders!
    }
    
    
    func getNextDbId() -> Int64 {
        if (nextDbId != -1) {
            nextDbId += 1
            return nextDbId
        }
        
        var dbId: Int64 = 1
        
        guard let db = SqlConnector.sharedInstance.db else {
            print("Database not available")
            return dbId
        }
        
        let className = String(describing: B.self)
        let query = "SELECT MAX(dbId) FROM \(className);"
        var stmt: OpaquePointer? = nil
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let maxId = sqlite3_column_int64(stmt, 0)
                dbId = maxId
            }
        } else {
            print("Failed to get max ID for \(className)")
        }
        
        sqlite3_finalize(stmt)
        
        nextDbId = dbId + 1
        return nextDbId
    }
}


