import AVFoundation

class IndexedAudioSource: AudioSource {
    func load(engine _: AVAudioEngine, playerNode _: AVAudioPlayerNode, speedControl _: AVAudioUnitVarispeed, position _: CMTime?, completionHandler _: @escaping AVAudioPlayerNodeCompletionHandler) throws {
        throw PluginError.runtimeError("no buffer")
    }

    func getDuration() -> CMTime {
        return CMTime.invalid
    }

    override func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        sequence.append(self)
        return treeIndex + 1
    }
}
