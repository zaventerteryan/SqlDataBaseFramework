//
//  SqlInfo.swift
//  PizzeriaManager
//
//  Created by Zaven Terteryan on 6/23/25.
//

import Foundation

@objc(SqlInfo)
class SqlInfo: SqlObject {
    @objc dynamic var dbVersion: Int = 0
    
    static func get() -> [SqlInfo] {
        return SqlDao<SqlInfo>.get(filter: "")
    }
}
