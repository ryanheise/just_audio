//
//  PluginErrors.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation

class PluginError: Error {
    var code: Int
    var message: String

    init(_ code: Int, _ message: String) {
        self.code = code
        self.message = message
    }
}
