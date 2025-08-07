//
//  Item.swift
//  Pomodoro
//
//  Created by 정성원 on 8/1/25.
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
