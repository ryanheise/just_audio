//
//  ProcessingState.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

enum ProcessingState: Int, Codable {
    case none, loading, buffering, ready, completed
}
