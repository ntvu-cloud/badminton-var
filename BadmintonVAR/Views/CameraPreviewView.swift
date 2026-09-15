import SwiftUI
import AVFoundation

public struct CameraPreviewView: View {
    @ObservedObject var camera = CameraManager.shared
    @ObservedObject var buffer: RollingBufferManager
    
    @State private var selectedPosition: CourtPosition = .backLineRight
    @State private var showSettings: Bool = false
    @State private var showHistory: Bool = false
    @State private var isCalibratingLine: Bool = false
    
    // Căn vạch trực tiếp trên Live Camera
    @State private var lineAngle: Double = 0.0
    @State private var lineOffset: CGSize = .zero
    @State private var lineWidth: CGFloat = 30.0
    @State private var isCornerMode: Bool = true
    
    // Khi Challenge được kích hoạt
    @State private var reviewVideoURL: URL?
    @State private var showReviewView: Bool = false
    
    // Lịch sử challenge
    @Binding var historyRecords: [ChallengeRecord]
    
    public init(buffer: RollingBufferManager, historyRecords: Binding<[ChallengeRecord]>) {
        self.buffer = buffer
        self._historyRecords = historyRecords
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // MARK: - Live Camera Viewfinder Layer
            LiveCameraRepresentable(session: camera.captureSession)
                .ignoresSafeArea()
                .onTapGesture { location in
                    camera.focusAndExpose(at: location)
                }
            
            // Vạch ảo căn chỉnh trên sân thời gian thực
            if isCalibratingLine {
                CourtLineOverlay(
                    isCalibrating: $isCalibratingLine,
                    lineAngle: $lineAngle,
                    lineOffset: $lineOffset,
                    lineWidth: $lineWidth,
                    isCornerMode: $isCornerMode
                )
            }
            
            // Focus Indicator Animation khi chạm màn hình
            if let focus = camera.focusPoint {
                Circle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .position(focus)
                    .transition(.opacity)
            }
            
            // MARK: - Live HUD Overlays
            VStack {
                // Top Header Bar
                topHeaderBar
                
                Spacer()
                
                // Bottom Control Center
                bottomControlBar
            }
            
            // Loading Overlay khi đang trích xuất video Challenge
            if buffer.isExporting {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                            .scaleEffect(1.6)
                        Text("ĐANG XUẤT ĐỆM 240 FPS...")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        Text("Trích xuất khoảnh khắc 6-8 giây gần nhất")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(24)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(16)
                }
            }
        }
        .sheet(isPresented: $showReviewView) {
            if let url = reviewVideoURL {
                VARReviewView(
                    videoURL: url,
                    courtPosition: selectedPosition,
                    onDismiss: {
                        showReviewView = false
                    },
                    onSaveRecord: { newRecord in
                        historyRecords.insert(newRecord, at: 0)
                    }
                )
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(records: $historyRecords)
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsSheet(camera: camera, selectedPosition: $selectedPosition)
        }
        .onAppear {
            camera.rollingBuffer = buffer
            camera.configureSession(targetFPS: 240)
            buffer.startBuffering()
        }
    }
    
    // MARK: - Top Header
    private var topHeaderBar: some View {
        HStack(spacing: 10) {
            // Huy hiệu FPS
            HStack(spacing: 6) {
                Circle()
                    .fill(camera.isHighSpeedActive ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text("\(Int(camera.currentFPS)) FPS")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(camera.isHighSpeedActive ? .green : .orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.75))
            .cornerRadius(20)
            
            // Vị trí quan sát trên sân
            Menu {
                ForEach(CourtPosition.allCases, id: \.self) { pos in
                    Button(pos.rawValue) {
                        selectedPosition = pos
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.yellow)
                    Text(selectedPosition.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.75))
                .cornerRadius(20)
            }
            
            Spacer()
            
            // Bật/tắt thước đo vạch
            Button(action: { isCalibratingLine.toggle() }) {
                Image(systemName: isCalibratingLine ? "ruler.fill" : "ruler")
                    .font(.system(size: 14))
                    .foregroundColor(isCalibratingLine ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Circle())
            }
            
            // Bật/tắt đèn chiếu rọi sân
            Button(action: { camera.toggleTorch() }) {
                Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 14))
                    .foregroundColor(camera.isTorchOn ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Circle())
            }
            
            // Cài đặt thông số màn trập
            Button(action: { showSettings.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Circle())
            }
            
            // Lịch sử pha bóng
            Button(action: { showHistory.toggle() }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    // MARK: - Bottom Control Bar & Nút CHALLENGE to nhất
    private var bottomControlBar: some View {
        VStack(spacing: 12) {
            // Nút KÍCH HOẠT CHALLENGE
            Button(action: triggerVARChallenge) {
                ZStack {
                    // Hiệu ứng vòng tròn tỏa sáng
                    Circle()
                        .stroke(Color.red.opacity(0.4), lineWidth: 8)
                        .frame(width: 96, height: 96)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color(red: 0.8, green: 0.1, blue: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 82, height: 82)
                        .shadow(color: .red.opacity(0.6), radius: 12, x: 0, y: 0)
                    
                    VStack(spacing: 2) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                        Text("CHALLENGE")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(buffer.isExporting)
            
            Text("Nhấn nút khi cầu vừa rơi để xem lại ngay 6 giây vừa qua")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .shadow(radius: 2)
        }
        .padding(.bottom, 24)
    }
    
    private func triggerVARChallenge() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        
        buffer.triggerChallenge { url in
            if let videoURL = url {
                self.reviewVideoURL = videoURL
                self.showReviewView = true
            }
        }
    }
}

// MARK: - LiveCameraRepresentable (AVCaptureVideoPreviewLayer)
struct LiveCameraRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - CameraSettingsSheet (Tùy chỉnh Shutter Speed chống nhòe)
struct CameraSettingsSheet: View {
    @ObservedObject var camera: CameraManager
    @Binding var selectedPosition: CourtPosition
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tốc độ khung hình (Frame Rate)")) {
                    HStack {
                        Text("Tốc độ hiện tại:")
                        Spacer()
                        Text("\(Int(camera.currentFPS)) FPS")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("Hỗ trợ tối đa:")
                        Spacer()
                        Text("\(Int(camera.maxSupportedFPS)) FPS")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Chống nhòe hình (Shutter Speed & ISO)")) {
                    Toggle("Khóa màn trập nhanh thủ công", isOn: Binding(
                        get: { camera.manualExposureEnabled },
                        set: { enabled in
                            if enabled {
                                camera.setManualShutter(numerator: camera.shutterSpeedNumerator, iso: camera.currentISO)
                            } else {
                                camera.resetToAutoExposure()
                            }
                        }
                    ))
                    
                    if camera.manualExposureEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tốc độ màn trập: 1/\(Int(camera.shutterSpeedNumerator))s")
                                .font(.system(size: 13, weight: .bold))
                            Slider(value: $camera.shutterSpeedNumerator, in: 240...2000, step: 60) { _ in
                                camera.setManualShutter(numerator: camera.shutterSpeedNumerator, iso: camera.currentISO)
                            }
                            Text("Tốc độ 1/500s - 1/1000s giúp bắt chết quả cầu không bị nhòe.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Độ nhạy sáng ISO: \(Int(camera.currentISO))")
                                .font(.system(size: 13, weight: .bold))
                            Slider(value: $camera.currentISO, in: camera.minISO...camera.maxISO, step: 50) { _ in
                                camera.setManualShutter(numerator: camera.shutterSpeedNumerator, iso: camera.currentISO)
                            }
                        }
                    }
                }
                
                Section(header: Text("Góc vạch quan sát mặc định")) {
                    Picker("Vị trí", selection: $selectedPosition) {
                        ForEach(CourtPosition.allCases, id: \.self) { pos in
                            Text(pos.rawValue).tag(pos)
                        }
                    }
                }
            }
            .navigationTitle("Cấu hình VAR")
            .navigationBarItems(trailing: Button("Xong") { dismiss() })
        }
    }
}
