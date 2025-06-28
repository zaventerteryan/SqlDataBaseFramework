//
//  SqlDataBase.swift
//  SqlDataBaseFramework
//
//  Created by Zaven Terteryan on 6/28/25.
//

import Foundation

open class SqlDataBase {
    static var shared: SqlDataBase = SqlDataBase()
    
    open func registerDao<T: SqlObject>(_ type: T.Type) {
        SqlConnector.sharedInstance.registerDao(type)
    }
    
    open func initDatabase(dbName: String, version: Int) {
        SqlConnector.sharedInstance.initDatabase(dbName: dbName, version: version)
    }
    
    open func get<T: SqlObjectProtocol>(filter: String) -> [T] {
        return SqlDao<T>.get(filter: filter)
    }
}
