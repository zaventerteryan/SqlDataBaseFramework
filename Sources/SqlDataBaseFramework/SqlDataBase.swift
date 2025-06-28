//
//  SqlDataBase.swift
//  SqlDataBaseFramework
//
//  Created by Zaven Terteryan on 6/28/25.
//

import Foundation

public class SqlDataBase {
    static var shared: SqlDataBase = SqlDataBase()
    
    func registerDao<T: SqlObject>(_ type: T.Type) {
        SqlConnector.sharedInstance.registerDao(type)
    }
    
    func initDatabase(dbName: String, version: Int) {
        SqlConnector.sharedInstance.initDatabase(dbName: dbName, version: version)
    }
    
    static func get<T: SqlObjectProtocol>(filter: String) -> [T] {
        return SqlDao<T>.get(filter: filter)
    }
}
