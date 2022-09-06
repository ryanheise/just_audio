import AVFoundation

class IndexedAudioSource: AudioSource {
    func load(engine _: AVAudioEngine, playerNode _: AVAudioPlayerNode, speedControl _: AVAudioUnitVarispeed, position _: CMTime?, completionHandler _: @escaping () -> Void) throws {
        throw NotImplementedError("Not implemented IndexedAudioSource.load")
    }

    func getDuration() -> CMTime {
        return CMTime.invalid
    }

    override func buildSequence() -> [IndexedAudioSource] {
        return [self]
    }
}
