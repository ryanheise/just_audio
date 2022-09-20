//
//  ConcatenatingInsertAllMessage.swift
//  just_audio
//
//  Created by Mac on 23/09/22.
//

class ConcatenatingInsertAllMessage {
    public let id: String
    public let index: Int
    public let children: [AudioSourceMessage]
    public let shuffleOrder: [Int]

    init(id: String, index: Int, children: [AudioSourceMessage], shuffleOrder: [Int]) {
        self.id = id
        self.index = index
        self.children = children
        self.shuffleOrder = shuffleOrder
    }

    static func fromMap(map: [String: Any]) -> ConcatenatingInsertAllMessage {
        let id = map["id"] as! String
        let index = map["index"] as! Int
        let shuffleOrder = map["shuffleOrder"] as! [Int]
        let children = (map["children"] as! [[String: Any]]).map {
            AudioSourceMessage.buildFrom(map: $0)
        }

        return ConcatenatingInsertAllMessage(
            id: id,
            index: index,
            children: children,
            shuffleOrder: shuffleOrder
        )
    }
}
