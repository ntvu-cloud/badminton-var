import SwiftUI

/// Kính lúp kỹ thuật số soi phóng đại mép vạch và đế cầu
public struct MagnifierLoupeView: View {
    @Binding public var zoomLevel: CGFloat
    @Binding public var loupePosition: CGPoint
    @Binding public var highContrast: Bool
    public var isInteractive: Bool = true
    
    public init(
        zoomLevel: Binding<CGFloat>,
        loupePosition: Binding<CGPoint>,
        highContrast: Binding<Bool>,
        isInteractive: Bool = true
    ) {
        self._zoomLevel = zoomLevel
        self._loupePosition = loupePosition
        self._highContrast = highContrast
        self.isInteractive = isInteractive
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let diameter: CGFloat = min(proxy.size.width, proxy.size.height) * 0.42
            
            ZStack {
                // Vòng tròn kính lúp
                Circle()
                    .stroke(LinearGradient(colors: [.yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.15))
                    )
                    .frame(width: diameter, height: diameter)
                    .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 5)
                
                // Tâm ngắm hồng ngoại / Chữ thập căn vạch
                ZStack {
                    // Trục ngang
                    Rectangle()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: diameter * 0.7, height: 1.5)
                    
                    // Trục dọc
                    Rectangle()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: 1.5, height: diameter * 0.7)
                    
                    // Tâm tròn nhỏ
                    Circle()
                        .stroke(Color.red, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    
                    // Vòng chia vạch milimet tượng trưng
                    Circle()
                        .stroke(Color.yellow.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: diameter * 0.5, height: diameter * 0.5)
                }
                
                // Nhãn hiển thị độ phóng đại
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text(String(format: "ZOOM %.1fx", zoomLevel))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(4)
                        
                        if highContrast {
                            Text("TƯƠNG PHẢN CAO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(width: diameter, height: diameter)
            }
            .position(loupePosition)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard isInteractive else { return }
                        loupePosition = CGPoint(
                            x: max(diameter / 2, min(value.location.x, proxy.size.width - diameter / 2)),
                            y: max(diameter / 2, min(value.location.y, proxy.size.height - diameter / 2))
                        )
                    }
            )
        }
    }
}
