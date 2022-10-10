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

    static func parseAudioSequenceFrom(map: [String: Any?]) throws -> ([(String, AudioEffect)], AudioSequence) {
        let message = map["audioSource"] as! [String: Any?]
        let type = FlutterAudioSourceType(rawValue: message["type"] as! String)!

        switch type {
        case .progressive, .clipping, .dash, .hls, .looping:
            let (effects, audioSource) = try FlutterAudioSourceType.parseAudioSourceFrom(map: message)
            return (effects, IndexedAudioSequence(with: audioSource))
        case .silence:
            throw SwiftJustAudioPluginError.notImplementedError(message: "SilenceAudio is not yet supported")
        case .concatenating:
            let audioSourcesAndEffects = try (message["children"] as! [[String: Any?]]).map { try FlutterAudioSourceType.parseAudioSourceFrom(map: $0) }
            let sequenceList = audioSourcesAndEffects.map { _, audioSource in
                audioSource
            }

            let effectsList = audioSourcesAndEffects.map { effects, _ in
                effects
            }
            return (effectsList.flatMap { $0 }, ConcatenatingAudioSequence(
                with: sequenceList
            ))
        }
    }

    static func parseAudioSourceFrom(map: [String: Any?]) throws -> ([(String, AudioEffect)], AudioSource) {
        let type = FlutterAudioSourceType(rawValue: map["type"] as! String)!

        var effects: [(String, AudioEffect)] = []
        if let rawEffects = map["effects"] as? [[String: Any?]] {
            effects = rawEffects.map { DarwinAudioEffect.parseEffectFrom(map: $0) }
        }

        switch type {
        case .progressive, .dash, .hls:
            let uri = map["uri"] as! String
            let isLocal = !uri.starts(with: "http")

            if isLocal {
                return (effects, LocalAudioSource(at: uri, effects: effects.map { _, effect in effect }))
            }

            return (effects, RemoteAudioSource(at: uri, effects: effects.map { _, effect in effect }))
        case .silence:
            throw SwiftJustAudioPluginError.notImplementedError(message: "SilenceAudio is not yet supported")
        case .concatenating:
            throw SwiftJustAudioPluginError.notImplementedError(message: "AudioSource cannot be concatenating")
        case .clipping:
            let (effects, audioSource) = try FlutterAudioSourceType.parseAudioSourceFrom(map: map["child"] as! [String: Any?])
            return (effects, try ClippingAudioSource(
                with: audioSource,
                from: Double(map["start"] as! Int),
                to: Double(map["end"] as! Int)
            ))
        case .looping:
            let (effects, audioSource) = try FlutterAudioSourceType.parseAudioSourceFrom(map: map["child"] as! [String: Any?])
            return (effects, LoopingAudioSource(
                with: audioSource,
                count: map["count"] as! Int
            ))
        }
    }
}
