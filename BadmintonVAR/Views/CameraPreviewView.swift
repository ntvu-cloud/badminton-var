import SwiftUI
import AVFoundation
import UIKit

public struct CameraPreviewView: View {
    @ObservedObject var camera = CameraManager.shared
    @ObservedObject var buffer: RollingBufferManager
    
    @State private var selectedPosition: CourtPosition = .backLineRight
    @State private var showSettings: Bool = false
    @State private var showHistory: Bool = false
    
    // MARK: - Căn vạch phối cảnh 3 điểm & Khóa góc
    @State private var showLineOverlay: Bool = true
    @State private var calibration: PerspectiveCalibrationData = .default
    @State private var isAutoDetecting: Bool = false
    @State private var detectionToast: String? = nil
    
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
            
            // Vạch ảo căn chỉnh 3 điểm trên sân thời gian thực
            if showLineOverlay {
                CourtLineOverlay(
                    calibration: $calibration,
                    positionKey: selectedPosition.rawValue,
                    isInteractive: !calibration.isLocked
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
            
            // Thông báo kết quả tự động bắt vạch (Toast Feedback)
            if let toast = detectionToast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: toast.contains("🎯") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(toast.contains("🎯") ? .green : .yellow)
                        Text(toast)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.92))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(toast.contains("🎯") ? Color.green.opacity(0.8) : Color.yellow.opacity(0.8), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: 4)
                    .padding(.top, 75)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .zIndex(99)
            }
            
            // MARK: - Live HUD Overlays
            VStack {
                // Top Header Bar
                topHeaderBar
                
                // Thanh công cụ căn vạch (Khi đang ở chế độ căn chỉnh chưa khóa)
                if showLineOverlay && !calibration.isLocked {
                    calibrationToolbar
                }
                
                Spacer()
                
                // Bottom Control Center
                bottomControlBar
            }
            
            // Loading Overlay khi đang trích xuất 30s video Challenge
            if buffer.isExporting {
                ZStack {
                    Color.black.opacity(0.75).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                            .scaleEffect(1.8)
                        Text("ĐANG TRÍCH XUẤT 30 GIÂY VAR...")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("Ghép nối trọn vẹn toàn bộ pha cầu 240 FPS")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(28)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(20)
                    .shadow(radius: 20)
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
            loadSavedCalibration(for: selectedPosition)
        }
        .onChange(of: selectedPosition) { newPos in
            loadSavedCalibration(for: newPos)
        }
    }
    
    // MARK: - Top Header (Thiết kế rộng rãi, chống tràn chữ)
    private var topHeaderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Huy hiệu FPS & Bộ đệm 30s
                HStack(spacing: 5) {
                    Circle()
                        .fill(camera.isHighSpeedActive ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("\(Int(camera.currentFPS)) FPS")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(camera.isHighSpeedActive ? .green : .orange)
                    Text("| 30s")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.8))
                .cornerRadius(18)
                .fixedSize(horizontal: true, vertical: false)
                
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
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(18)
                }
                
                // Nút Khóa / Mở Khóa Vạch Sân
                Button(action: toggleCalibrationLock) {
                    HStack(spacing: 4) {
                        Image(systemName: calibration.isLocked ? "lock.fill" : "lock.open.fill")
                            .foregroundColor(calibration.isLocked ? .green : .yellow)
                        Text(calibration.isLocked ? "ĐÃ KHÓA GÓC" : "ĐANG CĂN VẠCH")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(calibration.isLocked ? Color.black.opacity(0.8) : Color.orange.opacity(0.85))
                    .cornerRadius(18)
                }
                
                // Bật/tắt ẩn hiện vạch
                Button(action: { showLineOverlay.toggle() }) {
                    Image(systemName: showLineOverlay ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 13))
                        .foregroundColor(showLineOverlay ? .white : .gray)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
                
                // Bật/tắt đèn chiếu rọi sân
                Button(action: { camera.toggleTorch() }) {
                    Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 13))
                        .foregroundColor(camera.isTorchOn ? .yellow : .white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
                
                // Cài đặt thông số màn trập
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
                
                // Lịch sử pha bóng
                Button(action: { showHistory.toggle() }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
    }
    
    // MARK: - Thanh công cụ khi đang căn vạch
    private var calibrationToolbar: some View {
        HStack(spacing: 12) {
            // Nút Tự Động Bắt Vạch Sân
            Button(action: runAutoLineDetection) {
                HStack(spacing: 6) {
                    if isAutoDetecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(isAutoDetecting ? "ĐANG BẮT VẠCH..." : "🤖 TỰ ĐỘNG BẮT VẠCH")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
                .shadow(color: .yellow.opacity(0.4), radius: 5)
            }
            .disabled(isAutoDetecting)
            
            // Tinh chỉnh độ dày vạch
            HStack(spacing: 6) {
                Text("Độ dày:")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Slider(value: $calibration.lineWidth, in: 14...50, step: 2)
                    .frame(width: 85)
                    .accentColor(.yellow)
            }
            
            Spacer()
            
            // Nút Khóa góc
            Button(action: lockCalibration) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("KHÓA GÓC")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green)
                .cornerRadius(10)
                .shadow(color: .green.opacity(0.5), radius: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
    
    // MARK: - Bottom Control Bar & Nút CHALLENGE to nhất
    private var bottomControlBar: some View {
        VStack(spacing: 8) {
            Button(action: triggerVARChallenge) {
                ZStack {
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
            
            Text("Chạm Challenge để xem lại trọn vẹn 30 giây pha cầu vừa qua")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .shadow(radius: 2)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Quản lý Căn Vạch & Khóa
    private func toggleCalibrationLock() {
        calibration.isLocked.toggle()
        saveCalibration()
    }
    
    private func lockCalibration() {
        calibration.isLocked = true
        saveCalibration()
    }
    
    private func saveCalibration() {
        let key = "calibration_\(selectedPosition.rawValue)"
        if let encoded = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func loadSavedCalibration(for pos: CourtPosition) {
        let key = "calibration_\(pos.rawValue)"
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(PerspectiveCalibrationData.self, from: data) {
            self.calibration = decoded
        } else {
            self.calibration = .default
        }
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
    
    // MARK: - Tự Động Bắt Vạch Sân (Auto Line & Corner Snapping)
    private func runAutoLineDetection() {
        guard let pixelBuffer = camera.latestPixelBuffer else {
            showDetectionToast("⚠️ Chưa có khung hình từ Camera.")
            return
        }
        
        isAutoDetecting = true
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CourtLineDetector.shared.detectLines(in: pixelBuffer)
            
            DispatchQueue.main.async {
                self.isAutoDetecting = false
                if let detected = result {
                    self.calibration = detected
                    self.saveCalibration()
                    let successGen = UINotificationFeedbackGenerator()
                    successGen.notificationOccurred(.success)
                    self.showDetectionToast("🎯 ĐÃ TỰ ĐỘNG BẮT ĐÚNG GÓC VÀ MÉP VẠCH!")
                } else {
                    let warnGen = UINotificationFeedbackGenerator()
                    warnGen.notificationOccurred(.warning)
                    self.showDetectionToast("⚠️ Chưa nhận diện rõ vạch. Hãy hướng camera vào góc sân.")
                }
            }
        }
    }
    
    private func showDetectionToast(_ message: String) {
        withAnimation(.spring()) {
            self.detectionToast = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if self.detectionToast == message {
                withAnimation(.easeOut) {
                    self.detectionToast = nil
                }
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
