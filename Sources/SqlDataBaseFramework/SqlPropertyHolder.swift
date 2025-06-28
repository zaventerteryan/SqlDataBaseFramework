//
//  SqlPropertyHolder.swift
//  Project
//
//  Created by Zaven Terteryan on 9/2/24.
//  Copyright © 2024 Zangi Livecom Pte. Ltd. All rights reserved.
//

import Foundation

struct SqlPropertyHolder {
    let propertyName: String
    let propertyType: String
    
    func getSqlType() -> String {
        var sqlType = "INTEGER"
            
        if self.propertyType.hasPrefix("@") {
            sqlType = "TEXT"
        }
        
        return sqlType
    }
}
