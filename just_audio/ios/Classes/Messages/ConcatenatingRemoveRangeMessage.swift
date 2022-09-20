//
//  ConcatenatingRemoveRangeMessage.swift
//  just_audio
//
//  Created by Mac on 23/09/22.
//

class ConcatenatingRemoveRangeMessage {
    public let id: String
    public let startIndex: Int
    public let endIndex: Int
    public let shuffleOrder: [Int]

    init(id: String, startIndex: Int, endIndex: Int, shuffleOrder: [Int]) {
        self.id = id
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.shuffleOrder = shuffleOrder
    }

    static func fromMap(map: [String: Any]) -> ConcatenatingRemoveRangeMessage {
        let id = map["id"] as! String
        let startIndex = map["startIndex"] as! Int
        let endIndex = map["endIndex"] as! Int
        let shuffleOrder = map["shuffleOrder"] as! [Int]

        return ConcatenatingRemoveRangeMessage(
            id: id,
            startIndex: startIndex,
            endIndex: endIndex,
            shuffleOrder: shuffleOrder
        )
    }
}
