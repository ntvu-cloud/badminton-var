import SwiftUI
import AVKit
import Photos

public struct VARReviewView: View {
    public let videoURL: URL
    public let courtPosition: CourtPosition
    public var onDismiss: () -> Void
    public var onSaveRecord: (ChallengeRecord) -> Void
    
    // MARK: - Video Player State
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var duration: Double = 0.0
    @State private var currentTime: Double = 0.0
    @State private var playbackRate: Float = 0.1 // Mặc định quay chậm 0.1x
    @State private var currentFrameIndex: Int = 0
    @State private var totalFrames: Int = 0
    private let fps: Double = 240.0 // Chuẩn quay 240 FPS
    
    // MARK: - Kính lúp & Căn vạch
    @State private var loupeZoom: CGFloat = 4.0
    @State private var loupePosition: CGPoint = CGPoint(x: 200, y: 200)
    @State private var highContrast: Bool = false
    @State private var showCourtLine: Bool = true
    @State private var lineAngle: Double = 0.0
    @State private var lineOffset: CGSize = .zero
    @State private var lineWidth: CGFloat = 30.0
    @State private var isCornerMode: Bool = true
    
    // MARK: - Phán quyết & Lưu trữ
    @State private var currentVerdict: VARVerdict = .inconclusive
    @State private var saveSuccessAlert: Bool = false
    @State private var isSavingImage: Bool = false
    @State private var timeObserverToken: Any?
    
    public init(
        videoURL: URL,
        courtPosition: CourtPosition,
        onDismiss: @escaping () -> Void,
        onSaveRecord: @escaping (ChallengeRecord) -> Void
    ) {
        self.videoURL = videoURL
        self.courtPosition = courtPosition
        self.onDismiss = onDismiss
        self.onSaveRecord = onSaveRecord
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header Bar
                headerBar
                
                // MARK: - Video Player Viewport with Overlays
                ZStack {
                    if let player = player {
                        CustomVideoPlayerView(player: player)
                            .ignoresSafeArea()
                    } else {
                        ProgressView("Đang tải video siêu chậm 240 FPS...")
                            .foregroundColor(.white)
                    }
                    
                    // Thước đo vạch ảo
                    if showCourtLine {
                        CourtLineOverlay(
                            isCalibrating: .constant(false),
                            lineAngle: $lineAngle,
                            lineOffset: $lineOffset,
                            lineWidth: $lineWidth,
                            isCornerMode: $isCornerMode
                        )
                    }
                    
                    // Kính lúp phóng đại kỹ thuật số
                    MagnifierLoupeView(
                        zoomLevel: $loupeZoom,
                        loupePosition: $loupePosition,
                        highContrast: $highContrast
                    )
                    
                    // Con dấu phán quyết (Verdict Badge Watermark)
                    if currentVerdict != .inconclusive {
                        VStack {
                            HStack {
                                Spacer()
                                HStack(spacing: 6) {
                                    Image(systemName: currentVerdict.iconName)
                                    Text(currentVerdict.rawValue)
                                        .font(.system(size: 16, weight: .black))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(currentVerdict.color.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(radius: 6)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                
                // MARK: - Điều khiển tua từng khung hình (Frame Scrubber)
                controlsPanel
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanUpPlayer()
        }
        .alert("Đã lưu bằng chứng VAR!", isPresented: $saveSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Ảnh chụp khoảnh khắc chạm vạch kèm phán quyết \(currentVerdict.rawValue) đã được lưu vào Thư viện ảnh iPhone.")
        }
    }
    
    // MARK: - Header
    private var headerBar: some View {
        HStack {
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Trở lại Sân")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("PHÂN TÍCH VAR - SO KIM MÉT")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.yellow)
                Text(courtPosition.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: captureAndSaveSnapshot) {
                HStack(spacing: 4) {
                    Image(systemName: "camera.badge.ellipsis")
                    Text("Lưu Bằng Chứng")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }
    
    // MARK: - Controls Panel
    private var controlsPanel: some View {
        VStack(spacing: 10) {
            // Thanh Scrubber hiển thị thời gian & Frame chính xác
            VStack(spacing: 4) {
                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Text("Khung hình #\(currentFrameIndex) / \(totalFrames)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.yellow)
                    
                    Spacer()
                    
                    Text(formatTime(duration))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                Slider(value: Binding(
                    get: { currentTime },
                    set: { newTime in
                        seekTo(time: newTime)
                    }
                ), in: 0...max(duration, 0.01))
                .accentColor(.green)
            }
            .padding(.horizontal, 16)
            
            // Các nút nhích từng khung hình (1/240s)
            HStack(spacing: 12) {
                Button(action: { stepFrame(by: -5) }) {
                    Text("-5 Frame")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 65, height: 36)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                
                Button(action: { stepFrame(by: -1) }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Text("1 Frame")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 75, height: 36)
                    .background(Color.blue.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 48, height: 36)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(6)
                }
                
                Button(action: { stepFrame(by: 1) }) {
                    HStack(spacing: 2) {
                        Text("1 Frame")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 75, height: 36)
                    .background(Color.blue.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                
                Button(action: { stepFrame(by: 5) }) {
                    Text("+5 Frame")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 65, height: 36)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            
            // Tốc độ xem chậm & Phóng to
            HStack(spacing: 12) {
                // Tốc độ tua chậm
                HStack(spacing: 4) {
                    Text("Tốc độ:")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    ForEach([0.05, 0.1, 0.25, 0.5, 1.0], id: \.self) { rate in
                        Button(action: { setPlaybackRate(Float(rate)) }) {
                            Text(rate == 1.0 ? "1x" : "\(String(format: "%.2fx", rate))")
                                .font(.system(size: 10, weight: playbackRate == Float(rate) ? .black : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(playbackRate == Float(rate) ? Color.yellow : Color.gray.opacity(0.2))
                                .foregroundColor(playbackRate == Float(rate) ? .black : .white)
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                // Thu phóng Kính lúp
                HStack(spacing: 4) {
                    Text("Lúp:")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    ForEach([2.0, 4.0, 8.0], id: \.self) { z in
                        Button(action: { loupeZoom = CGFloat(z) }) {
                            Text("\(Int(z))x")
                                .font(.system(size: 10, weight: loupeZoom == CGFloat(z) ? .bold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(loupeZoom == CGFloat(z) ? Color.green : Color.gray.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // MARK: - Phán quyết cuối cùng (Verdict Buttons)
            HStack(spacing: 16) {
                Button(action: { setVerdict(.inCourt) }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("IN (TRONG SÂN)")
                            .font(.system(size: 15, weight: .black))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(currentVerdict == .inCourt ? Color.green : Color.green.opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green, lineWidth: currentVerdict == .inCourt ? 3 : 1)
                    )
                }
                
                Button(action: { setVerdict(.outOfCourt) }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("OUT (NGOÀI SÂN)")
                            .font(.system(size: 15, weight: .black))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(currentVerdict == .outOfCourt ? Color.red : Color.red.opacity(0.25))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: currentVerdict == .outOfCourt ? 3 : 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .background(Color.black.opacity(0.95))
    }
    
    // MARK: - Setup AVPlayer
    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.actionAtItemEnd = .pause
        self.player = avPlayer
        
        let asset = AVURLAsset(url: videoURL)
        Task {
            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                await MainActor.run {
                    self.duration = seconds
                    self.totalFrames = Int(seconds * fps)
                }
            }
        }
        
        // Quan sát thời gian thực
        let interval = CMTime(value: 1, timescale: CMTimeScale(fps))
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let sec = CMTimeGetSeconds(time)
            currentTime = sec
            currentFrameIndex = Int(sec * fps)
        }
    }
    
    private func cleanUpPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }
    
    // MARK: - Video Action Methods
    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.rate = playbackRate
            isPlaying = true
        }
    }
    
    private func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }
    
    private func seekTo(time: Double) {
        player?.pause()
        isPlaying = false
        let targetTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(fps))
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func stepFrame(by count: Int) {
        player?.pause()
        isPlaying = false
        let frameDuration = 1.0 / fps
        let newTime = max(0, min(duration, currentTime + Double(count) * frameDuration))
        seekTo(time: newTime)
    }
    
    private func setVerdict(_ verdict: VARVerdict) {
        currentVerdict = verdict
        let record = ChallengeRecord(
            position: courtPosition,
            verdict: verdict,
            videoPath: videoURL.path,
            notes: "Xác định tại khung hình #\(currentFrameIndex) (\(formatTime(currentTime)))"
        )
        onSaveRecord(record)
    }
    
    private func captureAndSaveSnapshot() {
        guard let p = player, let currentItem = p.currentItem else { return }
        let asset = currentItem.asset
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let time = CMTime(seconds: currentTime, preferredTimescale: CMTimeScale(fps))
        
        generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
            if let image = cgImage {
                let uiImage = UIImage(cgImage: image)
                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                DispatchQueue.main.async {
                    saveSuccessAlert = true
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", mins, secs, ms)
    }
}

// MARK: - UIViewRepresentable AVPlayer
struct CustomVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFit
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
