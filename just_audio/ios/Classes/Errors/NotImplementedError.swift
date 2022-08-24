//
//  NotImplementedError.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

class NotImplementedError: PluginError {
    init(_ message: String) {
        super.init(500, message)
    }
}
