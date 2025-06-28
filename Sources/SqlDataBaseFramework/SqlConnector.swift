//
//  SqlConnector.swift
//  Project
//
//  Created by Zaven Terteryan on 9/2/24.
//  Copyright © 2024 Zangi Livecom Pte. Ltd. All rights reserved.
//

import Foundation
import SQLite3

@objc
class SqlConnector: NSObject {
    @objc static let sharedInstance = SqlConnector()
    private var isStarted = false
    private var daos: [String: SqlDaoProtocol] = [:]
    private var isLogs: Bool = false
    private var dbName: String = "SqlDataBase"
    private var syncQueue: DispatchQueue = DispatchQueue(label: "SqlConnector")
    
    private var dbVersion: Int {
        get {
            let version = SqlInfo.get().first?.dbVersion ?? 0
            return version
        }
        set {
            let config = SqlInfo.get().first
            config?.dbVersion = newValue
            config?.save()
        }
    }
    
    var db: OpaquePointer? = nil
    
    private var path: String = ""
    var storePath: String {
        if path == "" {
            let fileManager = FileManager.default
            let appSupportDirectory = try! fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let dbURL = appSupportDirectory.appendingPathComponent(dbName).appendingPathComponent("\(dbName).sqlite")

            try? fileManager.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            print("📂 Database path: \(dbURL.path)")
            path = dbURL.path
        }
        
        return path
    }
    
    func initDatabase(dbName: String, version: Int) {
        if !self.isStarted {
            syncQueue.sync {
                if !self.isStarted {
                    print("Starting")
                    db = self.openDb()
                    
                    self.registerDao(SqlInfo.self)

                    if self.dbVersion == 0 {
                        self.createDb(db: db)
                    } else if(self.dbVersion != version) {
                        self.upgradeDb(db: db)
                    }
                    
                    self.isStarted = true
                    self.dbVersion = version
                    print("Started for number \(dbName)")
                }
            }
        }
    }
    
    func registerDao<T: SqlObject>(_ type: T.Type) {
        let key = String(describing: type)
        daos[key] = self.getDao(for: type)
    }
    
    func getDao(obj: SqlObjectProtocol) -> SqlDaoProtocol {
        let typeName = String(describing: obj.getType())
        return self.getDao(name: typeName)
    }
    
    func getDao(name: String) -> SqlDaoProtocol {
        return self.daos[name]!
    }
    
    private func createDb(db: OpaquePointer?){
        for (_, dao) in self.daos {
            dao.createTable(db: db)
        }
        
        self.getDao(for: SqlInfo.self).insert(object: SqlInfo())
    }
    
    func openDb() -> OpaquePointer? {
        var db: OpaquePointer? = nil
        if sqlite3_open(self.storePath, &db) != SQLITE_OK {
            print("Unable to open database. Verify that you created the directory described " +
                "in the Getting Started section.")
        }
        
        if sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("Failed to set journal mode to WAL: \(errMsg)")
        } else {
            print("Successfully enabled WAL mode.")
        }
        
        return db
    }
    
    private func upgradeDb(db: OpaquePointer?){
        if (db == nil){
            return
        }
        
        if (dbVersion < 2) {
            for dao in self.daos.values {
                dao.migrateTableIfNeeded(db: db)
            }
        }
    }
    
    @objc
    func closeDB() {
        self.closeDB(db: db)
    }
    
    func closeDB(db: OpaquePointer?) {
        if let db = self.db {
            sqlite3_close(db)
            self.db = nil
            self.isStarted = false
            self.path = ""
            print("sql db is closed")
        }
    }
    
    
    private let lock = NSLock()

    func getDao<T: SqlObjectProtocol>(for type: T.Type) -> SqlDao<T> {
        let key = String(describing: type)

        lock.lock()
        defer { lock.unlock() }

        if let existing = daos[key] as? SqlDao<T> {
            return existing
        } else {
            let newDao = SqlDao<T>()
            daos[key] = newDao
            return newDao
        }
    }
    
    deinit {
        self.closeDB()
    }
}

