import SwiftUI
import CoreMotion

@Observable
public final class MotionManager {
    public static let shared = MotionManager()

    public var pitch: Double = 0.0 // X-tilt
    public var roll: Double = 0.0  // Y-tilt

    private let motion = CMMotionManager()

    private init() {
        start()
    }

    public func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Low-pass filter for smooth liquid inertia
            let targetPitch = data.attitude.pitch
            let targetRoll = data.attitude.roll
            self.pitch = (self.pitch * 0.85) + (targetPitch * 0.15)
            self.roll = (self.roll * 0.85) + (targetRoll * 0.15)
        }
    }

    public func stop() {
        motion.stopDeviceMotionUpdates()
    }
}