//
//  Item.swift
//  Claude Usage Viewer
//
//  Created by BJ Blaker on 5/14/26.
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
