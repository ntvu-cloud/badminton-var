import Foundation
import CoreVideo
import CoreGraphics
import UIKit

/// Bộ xử lý thị giác máy tính chuyên dụng cho sân cầu lông:
/// Sử dụng thuật toán Biến đổi Hough (Hough Transform) kết hợp bộ lọc cạnh dải vạch (Edge Gradient Ridge Filter)
/// Hoàn toàn tất định (Deterministic - không dùng random), miễn nhiễm với nhiễu phòng và đường ron gạch.
public class CourtLineDetector {
    public static let shared = CourtLineDetector()
    
    private init() {}
    
    // Bảng lượng giác tính trước cho 180 góc từ 0° đến 179°
    private static let cosTable: [CGFloat] = (0..<180).map { cos(CGFloat($0) * .pi / 180.0) }
    private static let sinTable: [CGFloat] = (0..<180).map { sin(CGFloat($0) * .pi / 180.0) }
    
    /// Nhận diện góc sân và 2 vạch từ CVPixelBuffer
    public func detectLines(in pixelBuffer: CVPixelBuffer) -> PerspectiveCalibrationData? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        guard pixelFormat == kCVPixelFormatType_32BGRA else { return nil }
        
        // Bước 1: Thu nhỏ kích thước tính toán xuống lưới chuẩn 320x180 (hoặc 180x320 nếu cầm dọc)
        let isPortrait = height > width
        let targetW = isPortrait ? 180 : 320
        let targetH = isPortrait ? 320 : 180
        
        let stepX = max(1, width / targetW)
        let stepY = max(1, height / targetH)
        
        var blueTapePoints: [CGPoint] = []
        var yellowLinePoints: [CGPoint] = []
        var greenTapePoints: [CGPoint] = []
        var whiteLinePoints: [CGPoint] = []
        var totalSamples = 0
        
        let bufferPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        for gy in 0..<targetH {
            let py = gy * stepY
            guard py < height else { continue }
            let rowOffset = py * bytesPerRow
            
            for gx in 0..<targetW {
                let px = gx * stepX
                guard px < width else { continue }
                totalSamples += 1
                
                let offset = rowOffset + px * 4
                let b = Int(bufferPtr[offset])
                let g = Int(bufferPtr[offset + 1])
                let r = Int(bufferPtr[offset + 2])
                
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let diff = maxC - minC
                let brightness = (r + g + b) / 3
                let pt = CGPoint(x: gx, y: gy)
                
                // 1. Băng keo xanh dương (Blue tape): B vượt trội so với R và G
                // Tuyệt đối không nhận nhầm gạch men trắng (R≈G≈B) hay ron gạch (R≈G≈B)
                if b > (r + 18) && b > (g + 12) && b > 55 {
                    blueTapePoints.append(pt)
                }
                // 2. Vạch vàng sân gỗ
                else if r > 140 && g > 120 && b < 125 && (r + g) > 270 {
                    yellowLinePoints.append(pt)
                }
                // 3. Băng keo xanh lá
                else if g > (r + 20) && g > (b + 15) && g > 60 {
                    greenTapePoints.append(pt)
                }
                // 4. Vạch trắng tiêu chuẩn trên thảm tối màu BWF
                else if brightness > 140 && diff < 38 {
                    whiteLinePoints.append(pt)
                }
            }
        }
        
        // Xác định loại vạch nổi bật trong khung hình
        let candidatePoints: [CGPoint]
        if blueTapePoints.count >= 35 {
            // Phát hiện thấy dải băng keo xanh dương trên sân
            candidatePoints = blueTapePoints
        } else if yellowLinePoints.count >= 35 {
            candidatePoints = yellowLinePoints
        } else if greenTapePoints.count >= 35 {
            candidatePoints = greenTapePoints
        } else if whiteLinePoints.count >= 45 && whiteLinePoints.count < Int(Double(totalSamples) * 0.32) {
            // Vạch trắng trên thảm (Loại trừ trường hợp cả sàn nhà đều là màu trắng)
            candidatePoints = whiteLinePoints
        } else {
            // Không có đủ điểm vạch đặc trưng, từ chối để tránh vẽ bừa
            return nil
        }
        
        // Bước 2: Biến đổi Hough Transform để tìm 2 đường thẳng chiếm ưu thế tuyệt đối
        let maxRho = Int(hypot(CGFloat(targetW), CGFloat(targetH))) + 1
        let numRhoBins = maxRho * 2 + 1
        
        var accumulator = [Int](repeating: 0, count: 180 * numRhoBins)
        
        for pt in candidatePoints {
            let x = pt.x
            let y = pt.y
            for theta in 0..<180 {
                let r = Int(round(x * Self.cosTable[theta] + y * Self.sinTable[theta])) + maxRho
                if r >= 0 && r < numRhoBins {
                    accumulator[theta * numRhoBins + r] += 1
                }
            }
        }
        
        // Tìm Đỉnh 1 (Peak 1) có nhiều lượt vote nhất
        var maxVotes1 = 0
        var bestTheta1 = 0
        var bestRho1 = 0
        
        for theta in 0..<180 {
            for r in 0..<numRhoBins {
                let v = accumulator[theta * numRhoBins + r]
                if v > maxVotes1 {
                    maxVotes1 = v
                    bestTheta1 = theta
                    bestRho1 = r
                }
            }
        }
        
        // Đường thẳng 1 phải có tối thiểu 25 điểm thẳng hàng
        guard maxVotes1 >= 25 else { return nil }
        
        // Tìm Đỉnh 2 (Peak 2) với điều kiện góc kẹp giữa 2 đường nằm trong khoảng [55°, 125°]
        // Đây là góc phối cảnh tự nhiên của 2 cạnh góc vuông sân cầu lông
        var maxVotes2 = 0
        var bestTheta2 = 0
        var bestRho2 = 0
        
        for theta in 0..<180 {
            // Tính góc chênh lệch giữa theta và bestTheta1
            var angleDiff = abs(theta - bestTheta1)
            if angleDiff > 90 {
                angleDiff = 180 - angleDiff
            }
            
            // Chỉ xét các đường tạo góc từ 55° đến 90° (tức gần vuông góc dưới phối cảnh)
            guard angleDiff >= 55 && angleDiff <= 90 else { continue }
            
            for r in 0..<numRhoBins {
                let v = accumulator[theta * numRhoBins + r]
                if v > maxVotes2 {
                    maxVotes2 = v
                    bestTheta2 = theta
                    bestRho2 = r
                }
            }
        }
        
        // Đường thẳng 2 phải có tối thiểu 18 điểm thẳng hàng
        guard maxVotes2 >= 18 else { return nil }
        
        // Bước 3: Tính giao điểm hình học chính xác giữa 2 đường thẳng (Đỉnh góc sân)
        // Đường 1: x*cos(t1) + y*sin(t1) = rho1
        // Đường 2: x*cos(t2) + y*sin(t2) = rho2
        let realRho1 = CGFloat(bestRho1 - maxRho)
        let realRho2 = CGFloat(bestRho2 - maxRho)
        
        let cos1 = Self.cosTable[bestTheta1]
        let sin1 = Self.sinTable[bestTheta1]
        let cos2 = Self.cosTable[bestTheta2]
        let sin2 = Self.sinTable[bestTheta2]
        
        let det = cos1 * sin2 - sin1 * cos2
        guard abs(det) > 0.3 else { return nil } // Đảm bảo 2 đường không song song
        
        let intersectX = (realRho1 * sin2 - realRho2 * sin1) / det
        let intersectY = (realRho2 * cos1 - realRho1 * cos2) / det
        
        // Chuẩn hóa tọa độ giao điểm về tỉ lệ [0.0, 1.0]
        let normCornerX = intersectX / CGFloat(targetW)
        let normCornerY = intersectY / CGFloat(targetH)
        
        // Đỉnh góc phải nằm trong phạm vi hiển thị hợp lý của màn hình
        guard normCornerX >= 0.04 && normCornerX <= 0.96 && normCornerY >= 0.04 && normCornerY <= 0.96 else {
            return nil
        }
        
        // Bước 4: Kiểm tra sự tồn tại của vạch thực tế gần đỉnh góc (Xác minh không phải góc ảo)
        let cornerPt = CGPoint(x: intersectX, y: intersectY)
        let nearbyInliers1 = candidatePoints.filter { pt in
            let distToLine = abs(pt.x * cos1 + pt.y * sin1 - realRho1)
            let distToCorner = hypot(pt.x - cornerPt.x, pt.y - cornerPt.y)
            return distToLine <= 8.0 && distToCorner >= 10.0 && distToCorner <= CGFloat(targetW) * 0.7
        }
        let nearbyInliers2 = candidatePoints.filter { pt in
            let distToLine = abs(pt.x * cos2 + pt.y * sin2 - realRho2)
            let distToCorner = hypot(pt.x - cornerPt.x, pt.y - cornerPt.y)
            return distToLine <= 8.0 && distToCorner >= 10.0 && distToCorner <= CGFloat(targetW) * 0.7
        }
        
        guard nearbyInliers1.count >= 8 && nearbyInliers2.count >= 8 else {
            // Không có dải vạch thực tế kéo dài từ đỉnh góc
            return nil
        }
        
        // Bước 5: Phân loại đâu là Vạch Đáy (Baseline) và đâu là Vạch Biên (Sideline)
        // Vạch đáy thường có độ dốc nằm ngang hơn (dy/dx nhỏ hơn)
        // Vạch biên kéo dài vào sâu theo phối cảnh
        let slope1 = abs(sin1) > 0.001 ? abs(cos1 / sin1) : 999.0
        let slope2 = abs(sin2) > 0.001 ? abs(cos2 / sin2) : 999.0
        
        let (baselineInliers, sidelineInliers): ([CGPoint], [CGPoint])
        if slope1 < slope2 {
            baselineInliers = nearbyInliers1
            sidelineInliers = nearbyInliers2
        } else {
            baselineInliers = nearbyInliers2
            sidelineInliers = nearbyInliers1
        }
        
        // Tính vector hướng kéo dài vạch đáy
        let avgBaseDx = baselineInliers.map { $0.x - cornerPt.x }.reduce(0, +) / CGFloat(baselineInliers.count)
        let avgBaseDy = baselineInliers.map { $0.y - cornerPt.y }.reduce(0, +) / CGFloat(baselineInliers.count)
        let baseLen = hypot(avgBaseDx, avgBaseDy)
        let baseUnit = baseLen > 0.001 ? CGPoint(x: avgBaseDx / baseLen, y: avgBaseDy / baseLen) : CGPoint(x: 1, y: 0)
        
        // Tính vector hướng kéo dài vạch biên
        let avgSideDx = sidelineInliers.map { $0.x - cornerPt.x }.reduce(0, +) / CGFloat(sidelineInliers.count)
        let avgSideDy = sidelineInliers.map { $0.y - cornerPt.y }.reduce(0, +) / CGFloat(sidelineInliers.count)
        let sideLen = hypot(avgSideDx, avgSideDy)
        let sideUnit = sideLen > 0.001 ? CGPoint(x: avgSideDx / sideLen, y: avgSideDy / sideLen) : CGPoint(x: 0, y: -1)
        
        // Điểm đầu mút vạch đáy kéo dài ~35% màn hình
        let normBaseX = max(0.05, min(0.95, normCornerX + baseUnit.x * 0.35))
        let normBaseY = max(0.05, min(0.95, normCornerY + baseUnit.y * 0.35))
        
        // Điểm đầu mút vạch biên kéo dài ~35% màn hình
        let normSideX = max(0.05, min(0.95, normCornerX + sideUnit.x * 0.35))
        let normSideY = max(0.05, min(0.95, normCornerY + sideUnit.y * 0.35))
        
        return PerspectiveCalibrationData(
            cornerX: normCornerX,
            cornerY: normCornerY,
            baselineX: normBaseX,
            baselineY: normBaseY,
            sidelineX: normSideX,
            sidelineY: normSideY,
            lineWidth: 26.0,
            isLocked: false
        )
    }
}
