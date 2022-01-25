import AVFoundation

class ConcatenatingAudioSource: AudioSource {
    let audioSources: [AudioSource]
    
    init(sid: String, audioSources: [AudioSource]) {
        self.audioSources = audioSources
        super.init(sid: sid)
    }
    
    override func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        var index = treeIndex
        for source in audioSources {
            index = source.buildSequence(sequence: &sequence, treeIndex: index)
        }
        return index
    }
    
    override func getShuffleIndices() -> [Int] {
        var indexes = audioSources.enumerated().map({ (index, _) in
            return index
        })
        indexes.shuffle();
        return indexes;
    }
    
    
}
