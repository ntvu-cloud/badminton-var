import SwiftUI

/// Model lưu tọa độ 3 điểm căn chỉnh góc sân
public struct PerspectiveCalibrationData: Codable, Equatable {
    public var cornerX: CGFloat
    public var cornerY: CGFloat
    public var baselineX: CGFloat
    public var baselineY: CGFloat
    public var sidelineX: CGFloat
    public var sidelineY: CGFloat
    public var lineWidth: CGFloat
    public var isLocked: Bool
    
    public static var `default`: PerspectiveCalibrationData {
        PerspectiveCalibrationData(
            cornerX: 0.5,
            cornerY: 0.75,
            baselineX: 0.88,
            baselineY: 0.75,
            sidelineX: 0.5,
            sidelineY: 0.25,
            lineWidth: 26.0,
            isLocked: false
        )
    }
}

/// Thước đo vạch ảo căn 3 điểm phối cảnh: Mép ngoài luôn là ĐỎ (OUT), Mép trong luôn là XANH (IN)
public struct CourtLineOverlay: View {
    @Binding public var calibration: PerspectiveCalibrationData
    public var positionKey: String = "default"
    public var isInteractive: Bool = true
    
    public init(
        calibration: Binding<PerspectiveCalibrationData>,
        positionKey: String = "default",
        isInteractive: Bool = true
    ) {
        self._calibration = calibration
        self.positionKey = positionKey
        self.isInteractive = isInteractive
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            
            // Tọa độ 3 điểm thực tế trên màn hình
            let corner = CGPoint(x: calibration.cornerX * w, y: calibration.cornerY * h)
            let baseEnd = CGPoint(x: calibration.baselineX * w, y: calibration.baselineY * h)
            let sideEnd = CGPoint(x: calibration.sidelineX * w, y: calibration.sidelineY * h)
            let lineWidth = calibration.lineWidth
            
            // Vector hướng của vạch đáy (B) và vạch biên (S)
            let vB = CGPoint(x: baseEnd.x - corner.x, y: baseEnd.y - corner.y)
            let vS = CGPoint(x: sideEnd.x - corner.x, y: sideEnd.y - corner.y)
            
            // Tính toán vector pháp tuyến hướng vào LÒNG SÂN (Inside Normal) bằng tích vô hướng
            let nInsideB = calculateInsideNormal(along: vB, towards: vS)
            let nInsideS = calculateInsideNormal(along: vS, towards: vB)
            
            ZStack {
                // MARK: - 1. DẢI VẠCH SÂN 40MM (Vùng kẹp giữa mép đỏ và mép xanh - Chạm vào là IN)
                // Thân vạch đáy
                courtBand(corner: corner, arm: vB, insideNormal: nInsideB, width: lineWidth, extend: 1.5)
                    .fill(Color.green.opacity(0.24))
                
                // Thân vạch biên
                courtBand(corner: corner, arm: vS, insideNormal: nInsideS, width: lineWidth, extend: 1.5)
                    .fill(Color.green.opacity(0.24))
                
                // MARK: - 2. MÉP TRONG CỦA 2 VẠCH (XANH LÁ - Tiếp giáp lòng sân)
                // Mép trong vạch đáy
                courtEdge(corner: corner, arm: vB, insideNormal: nInsideB, offset: lineWidth, extend: 1.5)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.8, dash: [6, 4]))
                
                // Mép trong vạch biên
                courtEdge(corner: corner, arm: vS, insideNormal: nInsideS, offset: lineWidth, extend: 1.5)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.8, dash: [6, 4]))
                
                // MARK: - 3. MÉP NGOÀI CỦA CẢ 2 VẠCH (100% ĐỎ - CẦU VƯỢT QUA ĐÂY LÀ RA NGOÀI / OUT)
                // Mép ngoài vạch đáy (ĐỎ)
                courtEdge(corner: corner, arm: vB, insideNormal: nInsideB, offset: 0, extend: 1.5)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 2.5, dash: [7, 3]))
                
                // Mép ngoài vạch biên (ĐỎ)
                courtEdge(corner: corner, arm: vS, insideNormal: nInsideS, offset: 0, extend: 1.5)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 2.5, dash: [7, 3]))
                
                // MARK: - 4. Nhãn hướng dẫn trực quan
                if !calibration.isLocked {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("MÉP NGOÀI (ĐỎ): Cầu vượt qua mép này là OUT")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.red)
                        }
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("THÂN VẠCH (XANH): Chạm mép đỏ hoặc thân vạch là IN")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                    .position(x: min(max(180, corner.x), w - 180), y: max(40, corner.y - lineWidth - 35))
                }
                
                // MARK: - 5. Các điểm neo kéo thả (Chỉ hiện khi chưa khóa)
                if !calibration.isLocked && isInteractive {
                    // Điểm 1: Đỉnh góc ngoài cùng (Giao 2 mép Đỏ)
                    calibrationHandle(
                        point: corner,
                        color: .yellow,
                        title: "1. ĐỈNH GÓC (NGOÀI)",
                        icon: "cross.circle.fill"
                    ) { newPos in
                        calibration.cornerX = max(0.05, min(0.95, newPos.x / w))
                        calibration.cornerY = max(0.05, min(0.95, newPos.y / h))
                        saveCalibration()
                    }
                    
                    // Điểm 2: Hướng vạch đáy
                    calibrationHandle(
                        point: baseEnd,
                        color: .cyan,
                        title: "2. MÉP ĐÁY",
                        icon: "arrow.right.circle.fill"
                    ) { newPos in
                        calibration.baselineX = max(0.05, min(0.95, newPos.x / w))
                        calibration.baselineY = max(0.05, min(0.95, newPos.y / h))
                        saveCalibration()
                    }
                    
                    // Điểm 3: Hướng vạch biên
                    calibrationHandle(
                        point: sideEnd,
                        color: .orange,
                        title: "3. MÉP BIÊN",
                        icon: "arrow.up.circle.fill"
                    ) { newPos in
                        calibration.sidelineX = max(0.05, min(0.95, newPos.x / w))
                        calibration.sidelineY = max(0.05, min(0.95, newPos.y / h))
                        saveCalibration()
                    }
                }
            }
        }
        .onAppear {
            loadSavedCalibration()
        }
    }
    
    // MARK: - Thuật toán hình học tính Inside Normal hướng vào trong sân
    private func calculateInsideNormal(along arm: CGPoint, towards otherArm: CGPoint) -> CGPoint {
        let len = sqrt(arm.x * arm.x + arm.y * arm.y)
        guard len > 0 else { return CGPoint(x: 0, y: 1) }
        
        let ux = arm.x / len
        let uy = arm.y / len
        
        // 2 hướng vuông góc có thể có
        let n1 = CGPoint(x: -uy, y: ux)
        
        // Kiểm tra xem n1 có hướng về phía cánh tay kia (lòng sân) không bằng tích vô hướng
        let dot = n1.x * otherArm.x + n1.y * otherArm.y
        if dot > 0 {
            return n1
        } else {
            return CGPoint(x: uy, y: -ux)
        }
    }
    
    // Tạo dải vạch 40mm kẹp giữa mép ngoài và mép trong
    private func courtBand(corner: CGPoint, arm: CGPoint, insideNormal: CGPoint, width: CGFloat, extend: CGFloat) -> Path {
        let extArm = CGPoint(x: arm.x * extend, y: arm.y * extend)
        let p1 = corner
        let p2 = CGPoint(x: corner.x + extArm.x, y: corner.y + extArm.y)
        let p3 = CGPoint(x: p2.x + insideNormal.x * width, y: p2.y + insideNormal.y * width)
        let p4 = CGPoint(x: p1.x + insideNormal.x * width, y: p1.y + insideNormal.y * width)
        
        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.closeSubpath()
        return path
    }
    
    // Tạo đường kẻ mép (offset = 0 là Mép Ngoài ĐỎ; offset = width là Mép Trong XANH)
    private func courtEdge(corner: CGPoint, arm: CGPoint, insideNormal: CGPoint, offset: CGFloat, extend: CGFloat) -> Path {
        let extArm = CGPoint(x: arm.x * extend, y: arm.y * extend)
        let start = CGPoint(x: corner.x + insideNormal.x * offset, y: corner.y + insideNormal.y * offset)
        let end = CGPoint(x: corner.x + extArm.x + insideNormal.x * offset, y: corner.y + extArm.y + insideNormal.y * offset)
        
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
    
    // Điểm neo kéo thả
    private func calibrationHandle(
        point: CGPoint,
        color: Color,
        title: String,
        icon: String,
        onDrag: @escaping (CGPoint) -> Void
    ) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 46, height: 46)
            
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 30, height: 30)
            
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.9))
                .cornerRadius(4)
                .offset(y: 30)
        }
        .position(point)
        .gesture(
            DragGesture()
                .onChanged { value in
                    onDrag(value.location)
                }
        )
    }
    
    private func saveCalibration() {
        let key = "calibration_\(positionKey)"
        if let encoded = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func loadSavedCalibration() {
        let key = "calibration_\(positionKey)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PerspectiveCalibrationData.self, from: data) {
            self.calibration = decoded
        }
    }
}
