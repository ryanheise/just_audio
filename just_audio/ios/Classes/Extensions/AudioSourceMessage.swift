//
//  AudioSourceMessage.swift
//  just_audio
//
//  Created by Mac on 24/09/22.
//
import kMusicSwift

enum FlutterAudioSourceType: String {
    case progressive
    case dash
    case hls
    case silence
    case concatenating
    case clipping
    case looping
}

/**
 Extension utils to bridge hashmaps to kMusicSwift classes
 */
extension [String: Any?] {
    var audioSequence: AudioSequence {
        get throws {
            let message = self["audioSource"] as! [String: Any?]
            let type = FlutterAudioSourceType(rawValue: message["type"] as! String)!

            switch type {
            case .progressive, .clipping, .dash, .hls, .looping:
                return IndexedAudioSequence(with: try message.audioSource)
            case .silence:
                throw SwiftJustAudioPluginError.notImplementedError(message: "SilenceAudio is not yet supported")
            case .concatenating:
                return ConcatenatingAudioSequence(
                    with: try (message["children"] as! [[String: Any?]]).map { try $0.audioSource }
                )
            }
        }
    }

    var audioSource: AudioSource {
        get throws {
            let type = FlutterAudioSourceType(rawValue: self["type"] as! String)!

            var effects: [AudioEffect] = []
            if let rawEffects = self["effects"] as? [[String: Any?]] {
                effects = rawEffects.map { $0.audioEffect }
            }

            switch type {
            case .progressive, .dash, .hls:
                let uri = self["uri"] as! String

                if try isLocal {
                    return LocalAudioSource(at: uri, effects: effects)
                }

                return RemoteAudioSource(at: uri, effects: effects)
            case .silence:
                throw SwiftJustAudioPluginError.notImplementedError(message: "SilenceAudio is not yet supported")
            case .concatenating:
                throw SwiftJustAudioPluginError.notImplementedError(message: "AudioSource cannot be concatenating")
            case .clipping:
                return try ClippingAudioSource(
                    with: try (self["child"] as! [String: Any?]).audioSource,
                    from: Double(self["start"] as! Int),
                    to: Double(self["end"] as! Int)
                )
            case .looping:
                return LoopingAudioSource(
                    with: try (self["child"] as! [String: Any?]).audioSource,
                    count: self["count"] as! Int
                )
            }
        }
    }

    var isLocal: Bool {
        get throws {
            let uri = self["uri"] as! String

            return !uri.starts(with: "http")
        }
    }
}
