//
//  NotSupportedError.swift
//  just_audio
//
//  Created by kuama on 22/08/22.
//

import Foundation
class NotSupportedError: PluginError {
    var value: Any

    init(value: Any, _ message: String) {
        self.value = value
        super.init(400, "Not support \(value)\n\(message)")
    }
}
