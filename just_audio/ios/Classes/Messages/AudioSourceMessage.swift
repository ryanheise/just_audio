//
//  AudioSourceMessage.swift
//  just_audio
//
//  Created by Mac on 23/09/22.
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

class AudioSourceMessage {
    let id: String

    init(id: String) {
        self.id = id
    }

    static func buildFrom(map: [String: Any]) -> AudioSourceMessage {
        let type = FlutterAudioSourceType(rawValue: map["type"] as! String)!
        switch type {
        case .progressive:
            return UriAudioSourceMessage.fromMap(map: map)
        case .dash:
            return UriAudioSourceMessage.fromMap(map: map)
        case .hls:
            return UriAudioSourceMessage.fromMap(map: map)
        case .silence:
            return SilenceAudioSourceMessage.fromMap(map: map)
        case .concatenating:
            return ConcatenatingAudioSourceMessage.fromMap(map: map)
        case .clipping:
            return ClippingAudioSourceMessage.fromMap(map: map)
        case .looping:
            return LoopingAudioSourceMessage.fromMap(map: map)
        }
    }

    func toAudioSequence() throws -> AudioSequence {
        switch self {
        case let message as UriAudioSourceMessage:
            return IndexedAudioSequence(with: try message.toAudioSource())
        case is SilenceAudioSourceMessage:
            throw SwiftJustAudioPluginError.notImplementedError(message: "SilenceAudio is not yet supported")
        case let message as ConcatenatingAudioSourceMessage:
            return ConcatenatingAudioSequence(with: try message.children.map { try $0.toAudioSource()
            })
        case let message as ClippingAudioSourceMessage:
            return IndexedAudioSequence(with: try message.toAudioSource())
        case let message as LoopingAudioSourceMessage:
            return IndexedAudioSequence(with: try message.toAudioSource())
        default:
            throw SwiftJustAudioPluginError.notImplementedError(message: "Unknown AudioSourcetype")
        }
    }

    func toAudioSource() throws -> AudioSource {
        switch self {
        case let message as UriAudioSourceMessage:
            if message.isLocal {
                return LocalAudioSource(at: message.uri)
            }

            return RemoteAudioSource(at: message.uri)
        case is SilenceAudioSourceMessage:
            throw SwiftJustAudioPluginError.notImplementedError(message: "SilenceAudio is not yet supported")
        case is ConcatenatingAudioSourceMessage:
            throw SwiftJustAudioPluginError.notImplementedError(message: "AudioSource cannot be concatenating")
        case let message as ClippingAudioSourceMessage:
            return try ClippingAudioSource(
                with: try message.child.toAudioSource(),
                from: Double(message.start),
                to: Double(message.end)
            )
        case let message as LoopingAudioSourceMessage:
            return LoopingAudioSource(
                with: try message.child.toAudioSource(),
                count: message.count
            )
        default:
            throw SwiftJustAudioPluginError.notImplementedError(message: "Unknown AudioSourcetype")
        }
    }
}

class UriAudioSourceMessage: AudioSourceMessage {
    let uri: String
    let headers: [String: String]?

    var isLocal: Bool {
        return !uri.starts(with: "http")
    }

    init(uri: String, headers: [String: String]?, id: String) {
        self.uri = uri
        self.headers = headers
        super.init(id: id)
    }

    static func fromMap(map: [String: Any]) -> UriAudioSourceMessage {
        return UriAudioSourceMessage(
            uri: map["uri"] as! String,
            headers: map["headers"] as? [String: String],
            id: map["id"] as! String
        )
    }
}

class SilenceAudioSourceMessage: AudioSourceMessage {
    let duration: Int // microseconds

    init(duration: Int, id: String) {
        self.duration = duration
        super.init(id: id)
    }

    static func fromMap(map: [String: Any]) -> SilenceAudioSourceMessage {
        return SilenceAudioSourceMessage(
            duration: map["duration"] as! Int,
            id: map["id"] as! String
        )
    }
}

class ConcatenatingAudioSourceMessage: AudioSourceMessage {
    let children: [AudioSourceMessage]
    let useLazyPreparation: Bool
    public let shuffleOrder: [Int]

    init(children: [AudioSourceMessage], useLazyPreparation: Bool, shuffleOrder: [Int], id: String) {
        self.children = children
        self.useLazyPreparation = useLazyPreparation
        self.shuffleOrder = shuffleOrder
        super.init(id: id)
    }

    static func fromMap(map: [String: Any]) -> ConcatenatingAudioSourceMessage {
        return ConcatenatingAudioSourceMessage(
            children: (map["children"] as! [[String: Any]]).map { map in
                AudioSourceMessage.buildFrom(map: map)
            },
            useLazyPreparation: map["useLazyPreparation"] as! Bool,
            shuffleOrder: map["shuffleOrder"] as! [Int],
            id: map["id"] as! String
        )
    }
}

class ClippingAudioSourceMessage: AudioSourceMessage {
    let child: UriAudioSourceMessage

    let start: Int // microseconds
    let end: Int // microseconds

    init(child: UriAudioSourceMessage, start: Int, end: Int, id: String) {
        self.child = child
        self.start = start
        self.end = end
        super.init(id: id)
    }

    static func fromMap(map: [String: Any]) -> ClippingAudioSourceMessage {
        return ClippingAudioSourceMessage(
            child: UriAudioSourceMessage.fromMap(map: map["child"] as! [String: Any]),
            start: map["start"] as! Int,
            end: map["end"] as! Int,
            id: map["id"] as! String
        )
    }
}

class LoopingAudioSourceMessage: AudioSourceMessage {
    let child: UriAudioSourceMessage
    let count: Int

    init(child: UriAudioSourceMessage, count: Int, id: String) {
        self.child = child
        self.count = count
        super.init(id: id)
    }

    static func fromMap(map: [String: Any]) -> LoopingAudioSourceMessage {
        return LoopingAudioSourceMessage(
            child: UriAudioSourceMessage.fromMap(map: map["child"] as! [String: Any]),
            count: map["count"] as! Int,
            id: map["id"] as! String
        )
    }
}
