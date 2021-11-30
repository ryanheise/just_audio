
class AudioSource {
    let sourceId: String
    init(sid: String) {
        sourceId = sid
    }
    
    func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        return 0
    }
    
    func getShuffleIndices() -> [Int] {
        return []
    }
}
