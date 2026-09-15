import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import Combine

public class RollingBufferManager: NSObject, ObservableObject {
    @Published public var isRecording = false
    @Published public var bufferDuration: Double = 30.0 // Giữ lại 30 giây gần nhất
    @Published public var isExporting = false
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private let writerQueue = DispatchQueue(label: "com.badmintonvar.writerQueue")
    
    private var segmentIndex = 0
    private var segmentURLs: [URL] = []
    private var segmentStartTime: CMTime = .zero
    private var lastSampleTime: CMTime = .zero
    private let segmentTargetDuration: Double = 5.0 // Mỗi đoạn con 5 giây
    private let maxRetainedSegments: Int = 7 // 7 đoạn x 5s = 35s bộ đệm (luôn đảm bảo có trọn vẹn 30s)
    
    private var isFinalizingChallenge = false
    private var challengeCompletion: ((URL?) -> Void)?
    
    public override init() {
        super.init()
    }
    
    // MARK: - Bắt đầu bộ nhớ đệm vòng
    public func startBuffering() {
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.cleanTempFiles()
            self.segmentURLs.removeAll()
            self.segmentIndex = 0
            self.startNewSegment()
            DispatchQueue.main.async {
                self.isRecording = true
            }
        }
    }
    
    // MARK: - Dừng bộ nhớ đệm
    public func stopBuffering() {
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            self.finishCurrentWriter {
                DispatchQueue.main.async {
                    self.isRecording = false
                }
            }
        }
    }
    
    // MARK: - Nạp Frame từ Camera vào Buffer
    public func appendSample(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self = self, self.isRecording, !self.isFinalizingChallenge else { return }
            
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            self.lastSampleTime = pts
            
            // Khởi tạo thời gian bắt đầu đoạn con
            if self.segmentStartTime == .zero {
                self.segmentStartTime = pts
                self.assetWriter?.startSession(atSourceTime: pts)
            }
            
            // Kiểm tra thời lượng đoạn hiện tại, nếu vượt quá 5s thì xoay vòng sang đoạn mới
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, self.segmentStartTime))
            if elapsed >= self.segmentTargetDuration {
                self.rotateToNextSegment(at: pts)
                return
            }
            
            // Ghi frame vào input
            if let input = self.videoInput, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }
    }
    
    // MARK: - Kích hoạt CHALLENGE: Xuất toàn bộ 30 giây gần nhất thành video xem lại
    public func triggerChallenge(completion: @escaping (URL?) -> Void) {
        writerQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.isFinalizingChallenge = true
            DispatchQueue.main.async { self.isExporting = true }
            
            // Hoàn tất đoạn hiện tại
            self.finishCurrentWriter {
                // Ghép các đoạn video gần nhất (tối đa 30-35s) lại để có trọn vẹn cả pha cầu
                self.stitchRecentSegments { finalURL in
                    self.isFinalizingChallenge = false
                    DispatchQueue.main.async {
                        self.isExporting = false
                        completion(finalURL)
                    }
                    // Tự động khởi động lại buffer để sẵn sàng cho pha cầu tiếp theo
                    self.startNewSegment()
                }
            }
        }
    }
    
    // MARK: - Quản lý Segments (Xoay vòng file đệm)
    private func startNewSegment() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("var_segment_\(segmentIndex)_\(UUID().uuidString).mp4")
        
        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 28_000_000, // 28 Mbps cho độ nét cao ở 240fps
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            
            if writer.canAdd(input) {
                writer.add(input)
            }
            
            writer.startWriting()
            self.assetWriter = writer
            self.videoInput = input
            self.segmentStartTime = .zero
            self.segmentURLs.append(fileURL)
            self.segmentIndex += 1
            
            // Chỉ giữ tối đa 7 segments (~35 giây) trong bộ đệm tạm
            // Tự động xóa file cũ nhất để không bao giờ vượt quá ~100MB bộ nhớ tạm
            while self.segmentURLs.count > self.maxRetainedSegments {
                let oldURL = self.segmentURLs.removeFirst()
                try? FileManager.default.removeItem(at: oldURL)
            }
        } catch {
            print("Lỗi tạo AssetWriter: \(error)")
        }
    }
    
    private func rotateToNextSegment(at pts: CMTime) {
        self.finishCurrentWriter { [weak self] in
            guard let self = self else { return }
            self.startNewSegment()
            self.segmentStartTime = pts
            self.assetWriter?.startSession(atSourceTime: pts)
        }
    }
    
    private func finishCurrentWriter(completion: @escaping () -> Void) {
        guard let writer = self.assetWriter else {
            completion()
            return
        }
        
        self.videoInput?.markAsFinished()
        writer.finishWriting {
            completion()
        }
        self.assetWriter = nil
        self.videoInput = nil
    }
    
    // MARK: - Ghép nối các đoạn video trong 30 giây vừa qua
    private func stitchRecentSegments(completion: @escaping (URL?) -> Void) {
        let validURLs = self.segmentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else {
            completion(nil)
            return
        }
        
        // Nếu chỉ có 1 đoạn ngắn
        if validURLs.count == 1 {
            completion(validURLs.first)
            return
        }
        
        // Lấy tối đa 6 đoạn gần nhất (6 x 5s = 30s)
        let recentSegments = Array(validURLs.suffix(6))
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(recentSegments.last)
            return
        }
        
        var currentTime = CMTime.zero
        
        for url in recentSegments {
            let asset = AVURLAsset(url: url)
            if let track = asset.tracks(withMediaType: .video).first {
                let duration = asset.duration
                do {
                    try compositionTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: currentTime)
                    currentTime = CMTimeAdd(currentTime, duration)
                } catch {
                    print("Lỗi chèn track ghép video 30s: \(error)")
                }
            }
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("var_challenge_30s_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            completion(recentSegments.last)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false
        
        exportSession.exportAsynchronously {
            if exportSession.status == .completed {
                completion(outputURL)
            } else {
                print("Lỗi xuất ghép video: \(String(describing: exportSession.error))")
                completion(recentSegments.last)
            }
        }
    }
    
    private func cleanTempFiles() {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        if let files = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("var_") {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
