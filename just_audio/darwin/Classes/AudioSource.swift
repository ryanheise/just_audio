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
}
