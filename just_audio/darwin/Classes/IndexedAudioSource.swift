import AVFoundation

class IndexedAudioSource: AudioSource {
    func load(engine _: AVAudioEngine, playerNode _: AVAudioPlayerNode, speedControl _: AVAudioUnitVarispeed, completionHandler _: @escaping AVAudioPlayerNodeCompletionHandler) throws {
        throw PluginError.runtimeError("no buffer")
    }

    func getSampleRate() -> Double {
        return 0
    }

    func getSampleTime() -> Int64 {
        return 0
    }

    func getDuration() -> TimeInterval {
        return 0
    }

    override func buildSequence(sequence: inout [IndexedAudioSource], treeIndex: Int) -> Int {
        sequence.append(self)
        return treeIndex + 1
    }
}
