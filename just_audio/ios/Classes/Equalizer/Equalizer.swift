//
// JustAudioPlayer.swift
// kMusicSwift
// Created by Kuama Dev Team on 01/09/22
// Using Swift 5.0
// Running on macOS 12.5
//

import AVFoundation

public typealias PreSet = [Float]

private func equalizerNodeBuilder(frequencies: [Int]) -> AVAudioUnitEQ {
    let node = AVAudioUnitEQ(numberOfBands: frequencies.count)
    node.globalGain = 1
    for i in 0 ... (node.bands.count - 1) {
        node.bands[i].frequency = Float(frequencies[i])
        node.bands[i].gain = 0
        node.bands[i].filterType = .parametric
    }

    return node
}

public class Equalizer {
    public private(set) var frequencies: [Int]
    public private(set) var preSets: [PreSet] = []
    public private(set) var activePreset: PreSet?

    public static let defaultFrequencies = [32, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    public private(set) var node: AVAudioUnitEQ

    public init(frequencies: [Int] = defaultFrequencies, preSets: [PreSet] = []) throws {
        self.frequencies = frequencies
        node = equalizerNodeBuilder(frequencies: frequencies)
        try setPreSets(preSets)
    }

    public func setPreSets(_ preSets: [PreSet]) throws {
        for preSet in preSets {
            if preSet.count != frequencies.count {
                throw WrongPreSetForFrequencesError(preSet: preSet, frequencies: frequencies)
            }
        }

        self.preSets = preSets
    }

    public func activate(preset index: Int) throws {
        if !preSets.indices.contains(index) {
            throw PreSetNotFoundError(index, currentList: preSets)
        }

        let preset = preSets[index]

        for i in 0 ... (node.bands.count - 1) {
            node.bands[i].bypass = false
            node.bands[i].gain = preset[i]
        }

        activePreset = preset
    }

    public func resetGains() {
        for i in 0 ... (node.bands.count - 1) {
            node.bands[i].bypass = true
            node.bands[i].gain = 0
        }
        activePreset = nil
    }

    public func tweakBandGain(band index: Int, gain value: Float) throws {
        if !node.bands.indices.contains(index) {
            throw BandNotFoundError(bandIndex: index, bandsCount: node.bands.count)
        }

        node.bands[index].gain = value
    }
}
