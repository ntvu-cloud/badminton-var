import Foundation
import SwiftUI

/// Kết quả phán quyết của pha bóng tranh chấp
public enum VARVerdict: String, Codable, CaseIterable {
    case inCourt = "IN (TRONG SÂN)"
    case outOfCourt = "OUT (NGOÀI SÂN)"
    case inconclusive = "CHƯA XÁC ĐỊNH"
    
    public var color: Color {
        switch self {
        case .inCourt:
            return .green
        case .outOfCourt:
            return .red
        case .inconclusive:
            return .orange
        }
    }
    
    public var iconName: String {
        switch self {
        case .inCourt:
            return "checkmark.circle.fill"
        case .outOfCourt:
            return "xmark.circle.fill"
        case .inconclusive:
            return "questionmark.circle.fill"
        }
    }
}

/// Vị trí góc/vạch sân đang quan sát
public enum CourtPosition: String, Codable, CaseIterable {
    case backLineRight = "Vạch đáy - Phải"
    case backLineLeft = "Vạch đáy - Trái"
    case sideLineDoubles = "Vạch biên - Đôi"
    case sideLineSingles = "Vạch biên - Đơn"
    case frontServiceLine = "Vạch giao cầu ngắn"
    case centerLine = "Vạch trung tâm"
}

/// Bản ghi lịch sử một pha Challenge
public struct ChallengeRecord: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public var position: CourtPosition
    public var verdict: VARVerdict
    public var videoPath: String?
    public var snapshotPath: String?
    public var notes: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        position: CourtPosition = .backLineRight,
        verdict: VARVerdict = .inconclusive,
        videoPath: String? = nil,
        snapshotPath: String? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.position = position
        self.verdict = verdict
        self.videoPath = videoPath
        self.snapshotPath = snapshotPath
        self.notes = notes
    }
}
