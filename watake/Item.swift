//
//  Item.swift
//  watake
//
//  Created by mbairm3 on 23/07/26.
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
