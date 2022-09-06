//
//  NotInitializedError.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation
class NotInitializedError: PluginError {
    init(_ message: String) {
        super.init(403, message)
    }
}
