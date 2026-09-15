import Foundation
import AVFoundation
import SwiftUI
import Combine

public class CameraManager: NSObject, ObservableObject {
    public static let shared = CameraManager()
    
    // MARK: - Published Properties
    @Published public var isRunning = false
    @Published public var currentFPS: Double = 0
    @Published public var maxSupportedFPS: Double = 60
    @Published public var isHighSpeedActive = false
    @Published public var isTorchOn = false
    @Published public var manualExposureEnabled = false
    @Published public var shutterSpeedNumerator: Double = 500 // 1/500s
    @Published public var currentISO: Float = 400
    @Published public var minISO: Float = 50
    @Published public var maxISO: Float = 1600
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var focusPoint: CGPoint? = nil
    @Published public var errorMessage: String? = nil
    
    // MARK: - Capture Session & Devices
    public let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.badmintonvar.sessionQueue")
    
    // Link to Rolling Buffer
    public var rollingBuffer: RollingBufferManager?
    
    public override init() {
        super.init()
    }
    
    // MARK: - Setup Camera Session
    public func configureSession(targetFPS: Double = 240) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            
            // Tìm camera góc rộng tốt nhất
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Không tìm thấy Camera sau."
                }
                self.captureSession.commitConfiguration()
                return
            }
            self.videoDevice = device
            
            // Xóa input cũ nếu có
            if let currentInput = self.videoInput {
                self.captureSession.removeInput(currentInput)
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.videoInput = input
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Lỗi khởi tạo Camera Input: \(error.localizedDescription)"
                }
                self.captureSession.commitConfiguration()
                return
            }
            
            // Tìm format hỗ trợ 240 FPS hoặc 120 FPS
            self.configureHighSpeedFormat(for: device, targetFPS: targetFPS)
            
            // Thiết lập Video Data Output
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.videoOutput.alwaysDiscardsLateVideoFrames = false
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.badmintonvar.videoBufferQueue", qos: .userInteractive))
                self.captureSession.addOutput(self.videoOutput)
            }
            
            // Đảm bảo hướng video đúng (Landscape hoặc Portrait)
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeRight
                }
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .off // Tắt chống rung để có frame rate tối đa không bị trễ
                }
            }
            
            self.captureSession.commitConfiguration()
            
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isRunning = self.captureSession.isRunning
                if let dev = self.videoDevice {
                    self.minISO = dev.activeFormat.minISO
                    self.maxISO = dev.activeFormat.maxISO
                    self.currentISO = dev.iso
                }
            }
        }
    }
    
    // MARK: - Tìm kiếm & kích hoạt Format 240 FPS
    private func configureHighSpeedFormat(for device: AVCaptureDevice, targetFPS: Double) {
        var bestFormat: AVCaptureDevice.Format?
        var bestRange: AVFrameRateRange?
        var highestFPSFound: Double = 30
        
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            // Ưu tiên độ phân giải 1080p (1920x1080)
            let is1080p = (dimensions.width == 1920 && dimensions.height == 1080) || (dimensions.height == 1920 && dimensions.width == 1080)
            
            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate > highestFPSFound {
                    highestFPSFound = range.maxFrameRate
                }
                
                if range.maxFrameRate >= targetFPS {
                    if is1080p {
                        bestFormat = format
                        bestRange = range
                        break
                    } else if bestFormat == nil {
                        bestFormat = format
                        bestRange = range
                    }
                }
            }
            if bestFormat != nil && is1080p {
                break
            }
        }
        
        // Nếu không có 240, thử hạ xuống 120 FPS
        if bestFormat == nil && targetFPS > 120 {
            configureHighSpeedFormat(for: device, targetFPS: 120)
            return
        }
        
        do {
            try device.lockForConfiguration()
            if let format = bestFormat, let range = bestRange {
                device.activeFormat = format
                let targetDuration = CMTime(value: 1, timescale: CMTimeScale(range.maxFrameRate))
                device.activeVideoMinFrameDuration = targetDuration
                device.activeVideoMaxFrameDuration = targetDuration
                
                DispatchQueue.main.async {
                    self.maxSupportedFPS = range.maxFrameRate
                    self.currentFPS = range.maxFrameRate
                    self.isHighSpeedActive = range.maxFrameRate >= 120
                }
            } else {
                DispatchQueue.main.async {
                    self.maxSupportedFPS = highestFPSFound
                    self.currentFPS = highestFPSFound
                }
            }
            
            // Cài đặt Continuous Auto Focus
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Lỗi cấu hình tốc độ khung hình: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Chạm để lấy nét & đo sáng vào mép vạch (Tap to Focus)
    public func focusAndExpose(at point: CGPoint) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.focusPoint = point
            }
        } catch {
            print("Không thể lấy nét tại điểm: \(error)")
        }
    }
    
    // MARK: - Tốc độ màn trập thủ công (Triệt tiêu nhòe chuyển động khi đập cầu)
    public func setManualShutter(numerator: Double, iso: Float) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let shutterDuration = CMTime(value: 1, timescale: CMTimeScale(numerator))
            let clampedISO = max(device.activeFormat.minISO, min(iso, device.activeFormat.maxISO))
            
            device.setExposureModeCustom(duration: shutterDuration, iso: clampedISO) { _ in }
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.shutterSpeedNumerator = numerator
                self.currentISO = clampedISO
                self.manualExposureEnabled = true
            }
        } catch {
            print("Lỗi khóa màn trập: \(error)")
        }
    }
    
    public func resetToAutoExposure() {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.manualExposureEnabled = false
            }
        } catch {
            print("Lỗi reset auto exposure: \(error)")
        }
    }
    
    // MARK: - Đèn rọi sân (Torch)
    public func toggleTorch() {
        guard let device = videoDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                DispatchQueue.main.async { self.isTorchOn = false }
            } else {
                try device.setTorchModeOn(level: 1.0)
                DispatchQueue.main.async { self.isTorchOn = true }
            }
            device.unlockForConfiguration()
        } catch {
            print("Lỗi bật/tắt đèn pin: \(error)")
        }
    }
    
    // MARK: - Zoom quang/số
    public func setZoom(factor: CGFloat) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let clampedFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.zoomScale = clampedFactor
            }
        } catch {
            print("Lỗi zoom: \(error)")
        }
    }
    
    public func stopSession() {
        sessionQueue.async { [weak self] in
            if self?.captureSession.isRunning == true {
                self?.captureSession.stopRunning()
                DispatchQueue.main.async {
                    self?.isRunning = false
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Chuyển frame vào bộ đệm vòng (Rolling Buffer)
        rollingBuffer?.appendSample(sampleBuffer)
    }
}
