class ConcatenatingAudioSource: AudioSource {
    let audioSources: [AudioSource]
    let shuffleOrder: [Int]
    
    init(sid: String, audioSources: [AudioSource], shuffleOrder: [Int]) {
        self.audioSources = audioSources
        self.shuffleOrder = shuffleOrder
        super.init(sid: sid)
    }
    
    override func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        var index = treeIndex
        for source in audioSources {
            index = source.buildSequence(sequence: &sequence, treeIndex: index)
        }
        return index
    }
}
