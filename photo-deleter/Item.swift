//
//  Item.swift
//  photo-deleter
//
//  Created by Tom Planche on 22/01/2025.
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
