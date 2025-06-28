//
//  SqlObject.swift
//  Project
//
//  Created by Zaven Terteryan on 9/2/24.
//  Copyright © 2024 Zangi Livecom Pte. Ltd. All rights reserved.
//

import Foundation

@objc(SqlObject)
public class SqlObject: NSObject, SqlObjectProtocol {
    private var dbType: AnyClass? = nil
    public func getType() -> AnyClass {
        if dbType == nil {
            dbType = type(of: self)
        }
        return dbType!
    }
    
    private var dao: SqlDaoProtocol {
        return SqlConnector.sharedInstance.getDao(obj: self)
    }
    
    private var mDbId: Int64 = -1
    @objc dynamic public var dbId: Int64 {
        get {
            if mDbId == -1 {
                mDbId = self.dao.getNextDbId()
            }
            return mDbId
        }
        set {
            mDbId = newValue
        }
    }
    
    func save() {
        SqlConnector.sharedInstance.getDao(name: String(describing: self.getType())).insert(object: self)
    }
    
    func delete() {
        SqlConnector.sharedInstance.getDao(name: String(describing: self.getType())).delete(object: self)
    }
    
    required public override init() {
        super.init()
    }
}
