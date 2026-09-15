import SwiftUI

@main
struct BadmintonVARApp: App {
    @StateObject private var bufferManager = RollingBufferManager()
    @State private var historyRecords: [ChallengeRecord] = []
    
    init() {
        // Giữ màn hình luôn sáng khi đặt iPhone trên tripod quan sát sân
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    var body: some Scene {
        WindowGroup {
            CameraPreviewView(
                buffer: bufferManager,
                historyRecords: $historyRecords
            )
            .preferredColorScheme(.dark)
        }
    }
}
