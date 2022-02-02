import AVFoundation

class AudioSource {
    let sourceId: String
    
    init(sid: String) {
        sourceId = sid
    }

    func buildSequence(sequence _: inout [IndexedAudioSource], treeIndex _: Int) -> Int {
        return 0
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
            return ConcatenatingAudioSource(sid: data["id"] as! String, audioSources: try AudioSource.fromListJson(data["children"] as! [Dictionary<String, Any>]), shuffleOrder: data["shuffleOrder"] as! Array<Int>)
        default:
            throw PluginError.notSupported(type, "When decoding audio source")
        }
    }
    
}
