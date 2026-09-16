import Foundation
import CoreVideo
import CoreGraphics
import UIKit

/// Bộ xử lý thị giác máy tính tự động nhận diện góc sân và 2 đường vạch (Baseline & Sideline) bằng RANSAC 2-Line
public class CourtLineDetector {
    public static let shared = CourtLineDetector()
    
    private init() {}
    
    /// Mô hình đường thẳng dạng chuẩn: A*x + B*y + C = 0 với A^2 + B^2 = 1
    public struct LineModel {
        public var a: CGFloat
        public var b: CGFloat
        public var c: CGFloat
        
        public init(a: CGFloat, b: CGFloat, c: CGFloat) {
            let len = sqrt(a * a + b * b)
            if len > 0.0001 {
                self.a = a / len
                self.b = b / len
                self.c = c / len
            } else {
                self.a = 0
                self.b = 1
                self.c = 0
            }
        }
        
        /// Khoảng cách từ điểm tới đường thẳng
        public func distance(to point: CGPoint) -> CGFloat {
            return abs(a * point.x + b * point.y + c)
        }
    }
    
    /// Nhận diện góc sân và 2 vạch từ CVPixelBuffer thời gian thực (< 15ms)
    public func detectLines(in pixelBuffer: CVPixelBuffer) -> PerspectiveCalibrationData? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        guard pixelFormat == kCVPixelFormatType_32BGRA else { return nil }
        
        // Bước 1: Trích xuất các điểm ảnh ứng viên thuộc vạch sân
        // Hỗ trợ:
        // 1. Băng keo xanh dương (Blue tape) trên nền gạch men trắng (miễn nhiễm 100% với ron gạch)
        // 2. Băng keo xanh lá (Green tape) trên nền sáng
        // 3. Vạch sơn vàng (Yellow lines) trên sân gỗ
        // 4. Vạch sơn trắng (White lines) trên thảm sân chuẩn BWF
        let step = 6
        var blueTapePoints: [CGPoint] = []
        var greenTapePoints: [CGPoint] = []
        var yellowLinePoints: [CGPoint] = []
        var whiteLinePoints: [CGPoint] = []
        var totalScanned = 0
        
        let bufferPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        let startY = height / 6
        let endY = height - height / 12
        let startX = width / 12
        let endX = width - width / 12
        
        for y in stride(from: startY, to: endY, by: step) {
            let rowOffset = y * bytesPerRow
            for x in stride(from: startX, to: endX, by: step) {
                totalScanned += 1
                let pixelOffset = rowOffset + x * 4
                let b = Int(bufferPtr[pixelOffset])
                let g = Int(bufferPtr[pixelOffset + 1])
                let r = Int(bufferPtr[pixelOffset + 2])
                
                let maxC = max(r, max(g, b))
                let minC = min(r, min(g, b))
                let diff = maxC - minC
                let brightness = (r + g + b) / 3
                let pt = CGPoint(x: x, y: y)
                
                // 1. BĂNG KEO XANH DƯƠNG: Sắc tố Blue vượt trội (B > R + 20 và B > G + 15)
                // Hoàn toàn bỏ qua gạch men trắng (R≈G≈B) và ron gạch (R≈G≈B)
                if b > r + 20 && b > g + 15 && b > 60 {
                    blueTapePoints.append(pt)
                }
                // 2. BĂNG KEO XANH LÁ: Sắc tố Green vượt trội
                else if g > r + 25 && g > b + 20 && g > 60 {
                    greenTapePoints.append(pt)
                }
                // 3. VẠCH SƠN VÀNG: Sân gỗ thi đấu
                else if r > 140 && g > 130 && b < 125 && (r + g) > 280 {
                    yellowLinePoints.append(pt)
                }
                // 4. VẠCH TRẮNG TIÊU CHUẨN: Trên thảm tối màu
                else if brightness > 135 && diff < 40 {
                    whiteLinePoints.append(pt)
                }
            }
        }
        
        // Lựa chọn tập điểm ứng viên thông minh theo loại sân đang quan sát
        var candidatePoints: [CGPoint] = []
        if blueTapePoints.count >= 40 {
            // Sân dán băng keo xanh dương (như sân gạch men trắng của bạn)
            candidatePoints = blueTapePoints
        } else if yellowLinePoints.count >= 40 {
            // Sân gỗ thi đấu vạch vàng
            candidatePoints = yellowLinePoints
        } else if greenTapePoints.count >= 40 {
            // Sân dán băng keo xanh lá
            candidatePoints = greenTapePoints
        } else if whiteLinePoints.count >= 50 && whiteLinePoints.count < Int(Double(totalScanned) * 0.35) {
            // Vạch trắng trên thảm tối màu (Nếu > 35% thì là sàn nhà màu trắng, không phải vạch)
            candidatePoints = whiteLinePoints
        }
        
        guard candidatePoints.count >= 50 else { return nil }
        
        // Bước 2: Dùng RANSAC tìm đường thẳng thứ nhất (Line 1)
        guard let (line1, inliers1) = fitRansacLine(points: candidatePoints, iterations: 140, threshold: 6.0) else {
            return nil
        }
        guard inliers1.count >= 25 else { return nil }
        
        // Bước 3: Loại bỏ các điểm thuộc Line 1, tìm đường thẳng thứ hai (Line 2)
        let remainingPoints = candidatePoints.filter { line1.distance(to: $0) > 12.0 }
        guard remainingPoints.count >= 35 else { return nil }
        
        guard let (line2, inliers2) = fitRansacLineWithAngleConstraint(
            points: remainingPoints,
            referenceLine: line1,
            minAngleDeg: 35.0,
            maxAngleDeg: 145.0,
            iterations: 140,
            threshold: 6.0
        ) else {
            return nil
        }
        guard inliers2.count >= 20 else { return nil }
        
        // Bước 4: Tính giao điểm của Line 1 và Line 2 (Đỉnh góc sân thực tế)
        guard let intersect = intersectLines(line1: line1, line2: line2) else {
            return nil
        }
        
        let normCornerX = intersect.x / CGFloat(width)
        let normCornerY = intersect.y / CGFloat(height)
        
        // Giao điểm phải nằm trong hoặc sát khung hình màn hình
        guard normCornerX >= 0.02 && normCornerX <= 0.98 && normCornerY >= 0.02 && normCornerY <= 0.98 else {
            return nil
        }
        
        // Bước 5: Phân loại đâu là vạch đáy (Baseline) và đâu là vạch biên (Sideline)
        // Trong góc nhìn phối cảnh camera nghiêng:
        // Vạch đáy (Baseline) có xu hướng nằm ngang hơn (độ dốc |dy/dx| nhỏ hơn, hoặc |a/b| nhỏ hơn)
        // Vạch biên (Sideline) có xu hướng kéo dài sâu vào sân theo chiều dọc hướng về phía lưới
        let slope1 = abs(line1.b) > 0.001 ? abs(line1.a / line1.b) : 999.0
        let slope2 = abs(line2.b) > 0.001 ? abs(line2.a / line2.b) : 999.0
        
        let baselineLine: LineModel
        let baselineInliers: [CGPoint]
        let sidelineLine: LineModel
        let sidelineInliers: [CGPoint]
        
        if slope1 < slope2 {
            baselineLine = line1
            baselineInliers = inliers1
            sidelineLine = line2
            sidelineInliers = inliers2
        } else {
            baselineLine = line2
            baselineInliers = inliers2
            sidelineLine = line1
            sidelineInliers = inliers1
        }
        
        // Bước 6: Xác định hướng kéo dài của vạch đáy (theo hướng phân bố của các điểm inliers)
        let baseDir = directionVector(from: intersect, points: baselineInliers)
        let baseEnd = CGPoint(
            x: intersect.x + baseDir.x * CGFloat(width) * 0.35,
            y: intersect.y + baseDir.y * CGFloat(height) * 0.35
        )
        let normBaseX = max(0.05, min(0.95, baseEnd.x / CGFloat(width)))
        let normBaseY = max(0.05, min(0.95, baseEnd.y / CGFloat(height)))
        
        // Bước 7: Xác định hướng kéo dài của vạch biên (hướng về phía lưới / inliers)
        let sideDir = directionVector(from: intersect, points: sidelineInliers)
        let sideEnd = CGPoint(
            x: intersect.x + sideDir.x * CGFloat(width) * 0.35,
            y: intersect.y + sideDir.y * CGFloat(height) * 0.35
        )
        let normSideX = max(0.05, min(0.95, sideEnd.x / CGFloat(width)))
        let normSideY = max(0.05, min(0.95, sideEnd.y / CGFloat(height)))
        
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
    
    // MARK: - Thuật toán RANSAC tìm đường thẳng
    private func fitRansacLine(points: [CGPoint], iterations: Int, threshold: CGFloat) -> (LineModel, [CGPoint])? {
        var bestLine: LineModel?
        var bestInliers: [CGPoint] = []
        let count = points.count
        guard count >= 2 else { return nil }
        
        for _ in 0..<iterations {
            let idx1 = Int.random(in: 0..<count)
            var idx2 = Int.random(in: 0..<count)
            while idx2 == idx1 {
                idx2 = Int.random(in: 0..<count)
            }
            
            let p1 = points[idx1]
            let p2 = points[idx2]
            
            let dist = hypot(p2.x - p1.x, p2.y - p1.y)
            if dist < 25.0 { continue }
            
            // Đường thẳng qua p1 và p2: (y1 - y2)*x + (x2 - x1)*y + (x1*y2 - x2*y1) = 0
            let a = p1.y - p2.y
            let b = p2.x - p1.x
            let c = p1.x * p2.y - p2.x * p1.y
            let model = LineModel(a: a, b: b, c: c)
            
            var currentInliers: [CGPoint] = []
            for p in points {
                if model.distance(to: p) <= threshold {
                    currentInliers.append(p)
                }
            }
            
            if currentInliers.count > bestInliers.count {
                bestInliers = currentInliers
                bestLine = model
            }
        }
        
        guard let line = bestLine, bestInliers.count >= 15 else { return nil }
        
        // Tinh chỉnh bằng bình phương tối thiểu (Least Squares) trên tập inliers
        let refined = refineLineLeastSquares(points: bestInliers) ?? line
        return (refined, bestInliers)
    }
    
    // RANSAC tìm đường thẳng thứ hai có góc tạo với đường 1 nằm trong [minAngle, maxAngle]
    private func fitRansacLineWithAngleConstraint(
        points: [CGPoint],
        referenceLine: LineModel,
        minAngleDeg: CGFloat,
        maxAngleDeg: CGFloat,
        iterations: Int,
        threshold: CGFloat
    ) -> (LineModel, [CGPoint])? {
        var bestLine: LineModel?
        var bestInliers: [CGPoint] = []
        let count = points.count
        guard count >= 2 else { return nil }
        
        // Cosine của góc giữa 2 vector pháp tuyến
        let maxCos = cos(minAngleDeg * .pi / 180.0) // góc nhỏ nhất cho phép
        
        for _ in 0..<iterations {
            let idx1 = Int.random(in: 0..<count)
            var idx2 = Int.random(in: 0..<count)
            while idx2 == idx1 {
                idx2 = Int.random(in: 0..<count)
            }
            
            let p1 = points[idx1]
            let p2 = points[idx2]
            
            let dist = hypot(p2.x - p1.x, p2.y - p1.y)
            if dist < 25.0 { continue }
            
            let a = p1.y - p2.y
            let b = p2.x - p1.x
            let c = p1.x * p2.y - p2.x * p1.y
            let model = LineModel(a: a, b: b, c: c)
            
            // Kiểm tra góc giữa 2 đường thẳng: |dot(n1, n2)| <= cos(minAngle)
            let dot = abs(referenceLine.a * model.a + referenceLine.b * model.b)
            if dot > maxCos { continue } // Quá song song, bỏ qua
            
            var currentInliers: [CGPoint] = []
            for p in points {
                if model.distance(to: p) <= threshold {
                    currentInliers.append(p)
                }
            }
            
            if currentInliers.count > bestInliers.count {
                bestInliers = currentInliers
                bestLine = model
            }
        }
        
        guard let line = bestLine, bestInliers.count >= 15 else { return nil }
        let refined = refineLineLeastSquares(points: bestInliers) ?? line
        return (refined, bestInliers)
    }
    
    // Tinh chỉnh đường thẳng bằng Least Squares trên tập điểm
    private func refineLineLeastSquares(points: [CGPoint]) -> LineModel? {
        guard points.count >= 6 else { return nil }
        
        let n = CGFloat(points.count)
        let meanX = points.reduce(0) { $0 + $1.x } / n
        let meanY = points.reduce(0) { $0 + $1.y } / n
        
        var sxx: CGFloat = 0
        var syy: CGFloat = 0
        var sxy: CGFloat = 0
        
        for p in points {
            let dx = p.x - meanX
            let dy = p.y - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        
        // Dùng PCA / Eigenvector của ma trận hiệp phương sai 2D
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let a = -sin(angle)
        let b = cos(angle)
        let c = -(a * meanX + b * meanY)
        
        return LineModel(a: a, b: b, c: c)
    }
    
    // Giao điểm giữa A1*x + B1*y + C1 = 0 và A2*x + B2*y + C2 = 0
    private func intersectLines(line1: LineModel, line2: LineModel) -> CGPoint? {
        let det = line1.a * line2.b - line2.a * line1.b
        guard abs(det) > 0.05 else { return nil } // Hai đường gần như song song
        
        let x = (line1.b * line2.c - line2.b * line1.c) / det
        let y = (line2.a * line1.c - line1.a * line2.c) / det
        return CGPoint(x: x, y: y)
    }
    
    // Tìm vector hướng đơn vị từ điểm gốc hướng về phía tập điểm
    private func directionVector(from origin: CGPoint, points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint(x: 1, y: 0) }
        
        let sumDx = points.reduce(0) { $0 + ($1.x - origin.x) }
        let sumDy = points.reduce(0) { $0 + ($1.y - origin.y) }
        let len = hypot(sumDx, sumDy)
        guard len > 0.001 else { return CGPoint(x: 1, y: 0) }
        
        return CGPoint(x: sumDx / len, y: sumDy / len)
    }
}
