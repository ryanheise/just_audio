class IndexedAudioSource: AudioSource {
    var playerItem: IndexedPlayerItem? = nil
    var duration: CMTime = .invalid
    var position: CMTime = .invalid
    var bufferedPosition: CMTime = .invalid
    var isAttached = false

    override func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        sequence.append(self)
        return treeIndex + 1
    }
}
