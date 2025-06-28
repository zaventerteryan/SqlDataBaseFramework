//
//  SqlObjectProtocol.swift
//  Project
//
//  Created by Zaven Terteryan on 9/2/24.
//  Copyright © 2024 Zangi Livecom Pte. Ltd. All rights reserved.
//

import Foundation

protocol SqlObjectProtocol {
    var dbId: Int64 { get set }
    init()
    func getType() -> AnyClass
}
