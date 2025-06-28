//
//  SqlWrapper.swift
//  Project
//
//  Created by Zaven Terteryan on 9/2/24.
//  Copyright © 2024 Zangi Livecom Pte. Ltd. All rights reserved.
//

import Foundation

class SqlWrapper: NSObject, Codable {
    var dbString: String?
    var dbInt: Int?
    var dbId: Int64?
    var dbClassType: String?
    
    override init() {
        super.init()
    }
    
    convenience init(obj: Any) {
        self.init()
        
        if let valueString = obj as? String {
            let dbObj = SqlWrapper()
            dbObj.dbString = valueString
        } else if let valueInt = obj as? Int {
            let dbObj = SqlWrapper()
            dbObj.dbInt = valueInt
        } else if let valueSqlObject = obj as? SqlObject {
            self.dbClassType = String(describing: valueSqlObject.getType())
            self.dbId = valueSqlObject.dbId
        }
    }
    
    func toSqlObject() -> Any? {
        if (self.dbInt != nil){
            return self.dbInt!
        } else if (self.dbString != nil){
            return self.dbString!
        } else if (self.dbClassType != nil && self.dbId != nil){
            let dao = SqlConnector.sharedInstance.getDao(name: self.dbClassType!)
            if let obj = dao.get(dbId: self.dbId!) {
                return obj
            }
        }
        
        return nil
    }
    
    private func createInstance(className: String) -> SqlObjectProtocol? {
        guard let classType = NSClassFromString(className) as? NSObject.Type else {
            print("Error: Unable to get the class type from the class name.")
            return nil
        }

        return classType.init() as? SqlObjectProtocol
    }
    
    static func tryToConvertFromArray(json: UnsafePointer<UInt8>) -> [Any] {
        let jsonString = String(cString: json)
        var sqlObjects: [Any] = []
        
        guard let data = jsonString.data(using: .utf8) else {
            return sqlObjects
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let jsonArray = try? decoder.decode([SqlWrapper].self, from: data) else {
            return sqlObjects
        }
            
        for val in jsonArray {
            if let obj = val.toSqlObject() {
                sqlObjects.append(obj)
            }
        }
        
        return sqlObjects
    }
}
