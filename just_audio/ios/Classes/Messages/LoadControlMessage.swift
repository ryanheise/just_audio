//
//  LoadControlMessage.swift
//  just_audio
//
//  Created by Mac on 22/09/22.
//

/**
 Representation of the configuration of a player to be bootstrapped in `SwiftJustAudioPlugin` from Flutter
 */
class LoadControlMessage {
    let automaticallyWaitsToMinimizeStalling: Bool
    let preferredForwardBufferDuration: Int? // microseconds, maybe turn into a duration
    let canUseNetworkResourcesForLiveStreamingWhilePaused: Bool
    let preferredPeakBitRate: Double?

    private init(
        automaticallyWaitsToMinimizeStalling: Bool,
        preferredForwardBufferDuration: Int?,
        canUseNetworkResourcesForLiveStreamingWhilePaused: Bool,
        preferredPeakBitRate: Double?
    ) {
        self.automaticallyWaitsToMinimizeStalling = automaticallyWaitsToMinimizeStalling
        self.preferredForwardBufferDuration = preferredForwardBufferDuration
        self.canUseNetworkResourcesForLiveStreamingWhilePaused = canUseNetworkResourcesForLiveStreamingWhilePaused
        self.preferredPeakBitRate = preferredPeakBitRate
    }

    static func fromMap(map: [String: Any?]) -> LoadControlMessage {
        return LoadControlMessage(
            automaticallyWaitsToMinimizeStalling: map["automaticallyWaitsToMinimizeStalling"] as! Bool,
            preferredForwardBufferDuration: map["preferredForwardBufferDuration"] as? Int,
            canUseNetworkResourcesForLiveStreamingWhilePaused: map["canUseNetworkResourcesForLiveStreamingWhilePaused"] as! Bool, preferredPeakBitRate: map["preferredPeakBitRate"] as? Double
        )
    }
}
