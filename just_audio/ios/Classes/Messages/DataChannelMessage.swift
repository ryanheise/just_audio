//
//  DataChannelMessage.swift
//  audio_session
//
//  Created by Mac on 27/09/22.
//
import kMusicSwift

class DataChannelMessage: Equatable {
    let outputAbsolutePath: String?
    let outputError: Error?

    let playing: Bool?
    let volume: Float?
    let speed: Float?

    let loopMode: Int?
    let shuffleMode: Int?

    init(outputAbsolutePath: String?, outputError: Error?, playing: Bool, volume: Float?, speed: Float?, loopMode: LoopMode?, shuffleMode: Bool) {
        self.outputAbsolutePath = outputAbsolutePath
        self.outputError = outputError

        self.playing = playing
        self.volume = volume
        self.speed = speed

        self.shuffleMode = shuffleMode ? 1 : 0

        switch loopMode {
        case .off:
            self.loopMode = 0
        case .one:
            self.loopMode = 1
        case .all:
            self.loopMode = 2
        default:
            self.loopMode = nil
        }
    }

    func toMap() -> [String: Any?] {
        return [
            "outputAbsolutePath": outputAbsolutePath,
            "outputError": outputError != nil ? "\(String(describing: outputError))" : nil,

            "playing": playing,
            "volume": volume,
            "speed": speed,

            "loopMode": loopMode,
            "shuffleMode": shuffleMode,
        ]
    }

    static func == (lhs: DataChannelMessage, rhs: DataChannelMessage) -> Bool {
        lhs.outputAbsolutePath == rhs.outputAbsolutePath &&
            "\(String(describing: lhs.outputError))" == "\(String(describing: rhs.outputError))" &&

            lhs.playing == rhs.playing &&
            lhs.volume == rhs.volume &&
            lhs.speed == rhs.speed &&

            lhs.loopMode == rhs.loopMode &&
            lhs.shuffleMode == rhs.shuffleMode
    }
}
