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
            cornerY: 0.7,
            baselineX: 0.85,
            baselineY: 0.7,
            sidelineX: 0.5,
            sidelineY: 0.3,
            lineWidth: 26.0,
            isLocked: false
        )
    }
}

/// Thước đo vạch ảo căn 3 điểm phối cảnh (Góc sân, Vạch đáy, Vạch biên) + Khóa góc
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
            
            // Tọa độ thực tế theo kích thước màn hình
            let corner = CGPoint(x: calibration.cornerX * w, y: calibration.cornerY * h)
            let baseEnd = CGPoint(x: calibration.baselineX * w, y: calibration.baselineY * h)
            let sideEnd = CGPoint(x: calibration.sidelineX * w, y: calibration.sidelineY * h)
            let halfLine = calibration.lineWidth / 2.0
            
            ZStack {
                // MARK: - 1. Vẽ Thân Vạch Sân 40mm (Vùng chạm là IN)
                // Dải vạch đáy
                lineBand(from: corner, to: baseEnd, width: calibration.lineWidth, extend: 1.6)
                    .fill(Color.green.opacity(0.22))
                
                // Dải vạch biên
                lineBand(from: corner, to: sideEnd, width: calibration.lineWidth, extend: 1.6)
                    .fill(Color.green.opacity(0.22))
                
                // MARK: - 2. Mép Trong Của Vạch (Green Dashed)
                lineEdge(from: corner, to: baseEnd, offset: halfLine, extend: 1.6)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                
                lineEdge(from: corner, to: sideEnd, offset: halfLine, extend: 1.6)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                
                // MARK: - 3. Mép Ngoài Của Vạch (RED - Vượt qua đây là OUT)
                lineEdge(from: corner, to: baseEnd, offset: -halfLine, extend: 1.6)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                
                lineEdge(from: corner, to: sideEnd, offset: -halfLine, extend: 1.6)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                
                // MARK: - 4. Nhãn cảnh báo mép vạch khi chưa khóa
                if !calibration.isLocked {
                    Text("--- MÉP NGOÀI (CẦU VƯỢT QUA ĐÂY LÀ OUT) ---")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(4)
                        .position(x: corner.x, y: max(20, corner.y - calibration.lineWidth - 14))
                }
                
                // MARK: - 5. Các điểm neo kéo thả (Chỉ hiện khi chưa khóa)
                if !calibration.isLocked && isInteractive {
                    // Điểm 1: Đỉnh góc sân
                    calibrationHandle(
                        point: corner,
                        color: .yellow,
                        title: "1. GÓC SÂN",
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
                        title: "2. VẠCH ĐÁY",
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
                        title: "3. VẠCH BIÊN",
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
    
    // MARK: - Helper tạo dải vạch 40mm
    private func lineBand(from p1: CGPoint, to p2: CGPoint, width: CGFloat, extend: CGFloat) -> Path {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return Path() }
        
        let ux = (dx / len)
        let uy = (dy / len)
        // Vector vuông góc (pháp tuyến)
        let nx = -uy * (width / 2)
        let ny = ux * (width / 2)
        
        let extP2 = CGPoint(x: p1.x + dx * extend, y: p1.y + dy * extend)
        
        var path = Path()
        path.move(to: CGPoint(x: p1.x - nx, y: p1.y - ny))
        path.addLine(to: CGPoint(x: extP2.x - nx, y: extP2.y - ny))
        path.addLine(to: CGPoint(x: extP2.x + nx, y: extP2.y + ny))
        path.addLine(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
        path.closeSubpath()
        return path
    }
    
    // Helper tạo đường mép song song
    private func lineEdge(from p1: CGPoint, to p2: CGPoint, offset: CGFloat, extend: CGFloat) -> Path {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return Path() }
        
        let ux = dx / len
        let uy = dy / len
        let nx = -uy * offset
        let ny = ux * offset
        
        let extP2 = CGPoint(x: p1.x + dx * extend, y: p1.y + dy * extend)
        
        var path = Path()
        path.move(to: CGPoint(x: p1.x + nx, y: p1.y + ny))
        path.addLine(to: CGPoint(x: extP2.x + nx, y: extP2.y + ny))
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
                .frame(width: 48, height: 48)
            
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 32, height: 32)
            
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.85))
                .cornerRadius(4)
                .offset(y: 32)
        }
        .position(point)
        .gesture(
            DragGesture()
                .onChanged { value in
                    onDrag(value.location)
                }
        )
    }
    
    // MARK: - Lưu & Đọc cấu hình vào UserDefaults
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
