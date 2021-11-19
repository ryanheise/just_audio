import AVFAudio

class IndexedAudioSource: AudioSource {
    func load(engine: AVAudioEngine, player: AVAudioPlayerNode, completionHandler: @escaping AVAudioPlayerNodeCompletionHandler) throws {
        throw PluginError.runtimeError("no buffer")
    }
    
    func getDuration() -> TimeInterval {
        return 0
    }

    override func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        sequence.append(self)
        return treeIndex + 1
    }
}
