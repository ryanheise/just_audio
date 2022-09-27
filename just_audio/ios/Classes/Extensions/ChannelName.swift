//
//  ChannelName.swift
//  just_audio
//
//  Created by Mac on 27/09/22.
//

extension String {
    var methodsChannel: String {
        return String(format: "com.ryanheise.just_audio.methods.%@", self)
    }

    var eventsChannel: String {
        return String(format: "com.ryanheise.just_audio.events.%@", self)
    }

    var dataChannel: String {
        return String(format: "com.ryanheise.just_audio.data.%@", self)
    }
}
