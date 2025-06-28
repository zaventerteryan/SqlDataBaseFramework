//
//  SqlCache.swift
//  Project
//
//  Created by Zaven Terteryan on 9/2/24.
//  Copyright © 2024 Zangi Livecom Pte. Ltd. All rights reserved.
//

import Foundation

class SqlCache: NSObject {
    static let sharedInstance: SqlCache = SqlCache()
    var properties: [String: [SqlPropertyHolder]] = [:]
    var objs: [String: SqlObject] = [:]
}
