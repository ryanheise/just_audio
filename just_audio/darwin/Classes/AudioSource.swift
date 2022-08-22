import AVFoundation

class AudioSource {
    let sourceId: String

    init(sid: String) {
        sourceId = sid
    }

    func buildSequence() -> [IndexedAudioSource] {
        return []
    }

    func getShuffleIndices() -> [Int] {
        return []
    }

    static func fromListJson(_ data: [[String: Any]]) throws -> [AudioSource] {
        return try data.map { item in
            try AudioSource.fromJson(item)
        }
    }

    static func fromJson(_ data: [String: Any]) throws -> AudioSource {
        let type = data["type"] as! String

        switch type {
        case "progressive":
            return UriAudioSource(sid: data["id"] as! String, uri: data["uri"] as! String)
        case "concatenating":
            return ConcatenatingAudioSource(sid: data["id"] as! String, audioSources: try AudioSource.fromListJson(data["children"] as! [[String: Any]]), shuffleOrder: data["shuffleOrder"] as! [Int])
        default:
            throw NotSupportedError(value: type, "When decoding audio source")
        }
    }
}
