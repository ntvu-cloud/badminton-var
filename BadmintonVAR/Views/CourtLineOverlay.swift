import SwiftUI

/// Thước đo ảo căn chỉnh đường vạch sân tiêu chuẩn (40mm)
public struct CourtLineOverlay: View {
    @Binding public var isCalibrating: Bool
    @Binding public var lineAngle: Double // Góc nghiêng của vạch
    @Binding public var lineOffset: CGSize // Tọa độ dịch chuyển
    @Binding public var lineWidth: CGFloat // Độ rộng hiển thị của vạch (tỷ lệ 40mm)
    @Binding public var isCornerMode: Bool // Hiển thị góc chữ L hay vạch thẳng
    
    public init(
        isCalibrating: Binding<Bool>,
        lineAngle: Binding<Double>,
        lineOffset: Binding<CGSize>,
        lineWidth: Binding<CGFloat>,
        isCornerMode: Binding<Bool>
    ) {
        self._isCalibrating = isCalibrating
        self._lineAngle = lineAngle
        self._lineOffset = lineOffset
        self._lineWidth = lineWidth
        self._isCornerMode = isCornerMode
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2 + lineOffset.width, y: proxy.size.height / 2 + lineOffset.height)
            
            ZStack {
                // Vạch chuẩn mép ngoài (Mép quyết định OUT)
                Path { path in
                    let length = proxy.size.width * 1.5
                    path.move(to: CGPoint(x: center.x - length / 2, y: center.y - lineWidth / 2))
                    path.addLine(to: CGPoint(x: center.x + length / 2, y: center.y - lineWidth / 2))
                    
                    if isCornerMode {
                        path.move(to: CGPoint(x: center.x - lineWidth / 2, y: center.y - length / 2))
                        path.addLine(to: CGPoint(x: center.x - lineWidth / 2, y: center.y + length / 2))
                    }
                }
                .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                
                // Thân vạch 40mm (Vùng an toàn IN)
                Path { path in
                    let length = proxy.size.width * 1.5
                    path.addRect(CGRect(x: center.x - length / 2, y: center.y - lineWidth / 2, width: length, height: lineWidth))
                    
                    if isCornerMode {
                        path.addRect(CGRect(x: center.x - lineWidth / 2, y: center.y - length / 2, width: lineWidth, height: length))
                    }
                }
                .fill(Color.green.opacity(0.2))
                
                // Vạch mép trong
                Path { path in
                    let length = proxy.size.width * 1.5
                    path.move(to: CGPoint(x: center.x - length / 2, y: center.y + lineWidth / 2))
                    path.addLine(to: CGPoint(x: center.x + length / 2, y: center.y + lineWidth / 2))
                    
                    if isCornerMode {
                        path.move(to: CGPoint(x: center.x + lineWidth / 2, y: center.y - length / 2))
                        path.addLine(to: CGPoint(x: center.x + lineWidth / 2, y: center.y + length / 2))
                    }
                }
                .stroke(Color.green.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                
                // Nhãn giải thích mép vạch
                if isCalibrating {
                    VStack {
                        Text("--- MÉP NGOÀI (NẰM QUA ĐÂY LÀ OUT) ---")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                            .background(Color.black.opacity(0.7))
                            .padding(.horizontal, 4)
                        
                        Spacer().frame(height: lineWidth + 4)
                        
                        Text("--- VÙNG VẠCH SÂN 40MM (CHẠM LÀ IN) ---")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .background(Color.black.opacity(0.7))
                            .padding(.horizontal, 4)
                    }
                    .position(center)
                }
            }
            .rotationEffect(.degrees(lineAngle), anchor: .center)
            .gesture(
                isCalibrating ?
                DragGesture()
                    .onChanged { value in
                        lineOffset = CGSize(
                            width: lineOffset.width + value.translation.width * 0.1,
                            height: lineOffset.height + value.translation.height * 0.1
                        )
                    }
                : nil
            )
        }
    }
}
