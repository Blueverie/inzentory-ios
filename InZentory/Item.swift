//
//  Item.swift
//  InZentory
//
//  Created by Blueverie on 3/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
