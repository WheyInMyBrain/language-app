import SwiftUI
import AVFoundation

@Observable
@MainActor
public final class AudioBarViewModel: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    public private(set) var isRecording = false
    public private(set) var isPlaying = false
    public private(set) var isPendingSync = false
    public private(set) var currentDuration: Double = 0
    public private(set) var elapsedPlayback: Double = 0
    public private(set) var audioLevels: [CGFloat] = Array(repeating: 0.15, count: 24)

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var writeIndex = 0

    private var tempRecordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
    }

    public func toggleRecording(
        lang: String,
        date: String,
        category: String,
        index: Int,
        onFinish: @escaping (Double) -> Void
    ) {
        if isRecording {
            stopRecording(lang: lang, date: date, category: category, index: index, onFinish: onFinish)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let tempURL = tempRecordingURL
            let rec = try AVAudioRecorder(url: tempURL, settings: settings)
            rec.delegate = self
            rec.isMeteringEnabled = true
            rec.record()

            self.recorder = rec
            self.isRecording = true
            self.currentDuration = 0
            self.audioLevels = Array(repeating: 0.15, count: 24)
            self.writeIndex = 0

            meterTask?.cancel()
            meterTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(40))
                    guard let self, let rec = self.recorder, rec.isRecording else { break }
                    rec.updateMeters()
                    let power = rec.averagePower(forChannel: 0)
                    let normalized = max(0.08, CGFloat(pow(10.0, power / 20.0)))

                    self.audioLevels[self.writeIndex % 24] = normalized
                    self.writeIndex += 1
                    self.currentDuration = rec.currentTime
                }
            }
        } catch {
            print("[AudioBar] Failed to start recording: \(error)")
        }
    }

    public func stopRecording(
        lang: String,
        date: String,
        category: String,
        index: Int,
        onFinish: @escaping (Double) -> Void
    ) {
        meterTask?.cancel()
        meterTask = nil

        guard let rec = recorder else { return }
        let recordedURL = rec.url
        let finalDuration = rec.currentTime > 0 ? rec.currentTime : currentDuration
        rec.stop()
        self.recorder = nil
        self.isRecording = false
        self.currentDuration = finalDuration

        // Dispatch to background sync engine (uploads and deletes locally)
        Task {
            await AudioSyncEngine.shared.saveAudioRecord(
                lang: lang,
                date: date,
                category: category,
                index: index,
                sourceFileURL: recordedURL,
                duration: finalDuration
            )
            onFinish(finalDuration)
        }
    }

    public func togglePlayback(
        lang: String,
        date: String,
        category: String,
        index: Int,
        initialDuration: Double
    ) {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback(lang: lang, date: date, category: category, index: index, initialDuration: initialDuration)
        }
    }

    private func startPlayback(
        lang: String,
        date: String,
        category: String,
        index: Int,
        initialDuration: Double
    ) {
        let (resolvedURL, isPending) = AudioSyncEngine.shared.resolveAudioSource(
            lang: lang,
            date: date,
            category: category,
            index: index,
            hasDuration: initialDuration
        )
        guard let url = resolvedURL else { return }
        self.isPendingSync = isPending

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            // Direct file playback or streaming
            let p: AVAudioPlayer
            if url.isFileURL {
                p = try AVAudioPlayer(contentsOf: url)
            } else {
                // Background cache stream for remote server endpoints
                guard let data = try? Data(contentsOf: url) else { return }
                p = try AVAudioPlayer(data: data)
            }

            p.delegate = self
            p.play()
            self.player = p
            self.isPlaying = true

            playbackTask?.cancel()
            playbackTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard let self, let p = self.player, p.isPlaying else {
                        self?.stopPlayback()
                        break
                    }
                    self.elapsedPlayback = p.currentTime
                }
            }
        } catch {
            print("[AudioBar] Playback failed: \(error)")
        }
    }

    public func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        elapsedPlayback = 0
    }

    public func teardown() {
        meterTask?.cancel()
        meterTask = nil
        playbackTask?.cancel()
        playbackTask = nil
        if isRecording { recorder?.stop() }
        if isPlaying { player?.stop() }
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopPlayback()
        }
    }
}

public struct AudioBarView: View {
    public let lang: String
    public let date: String
    public let category: String
    public let index: Int
    public let initialDuration: Double
    public let accentColor: Color
    public var onDurationChange: ((Double) -> Void)? = nil

    @State private var vm = AudioBarViewModel()

    public init(
        lang: String,
        date: String,
        category: String,
        index: Int,
        initialDuration: Double = 0,
        accentColor: Color,
        onDurationChange: ((Double) -> Void)? = nil
    ) {
        self.lang = lang
        self.date = date
        self.category = category
        self.index = index
        self.initialDuration = initialDuration
        self.accentColor = accentColor
        self.onDurationChange = onDurationChange
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if vm.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(formatTime(vm.currentDuration))
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                } else if initialDuration > 0 || vm.currentDuration > 0 {
                    Button {
                        vm.togglePlayback(lang: lang, date: date, category: category, index: index, initialDuration: initialDuration)
                    } label: {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accentColor)
                            .frame(width: 30, height: 30)
                            .background(accentColor.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(AudioSquishButtonStyle())

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(formatTime(vm.isPlaying ? vm.elapsedPlayback : (vm.currentDuration > 0 ? vm.currentDuration : initialDuration)))
                                .font(.caption2.monospacedDigit().bold())

                            if vm.isPendingSync {
                                Image(systemName: "icloud.and.arrow.up")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                            }
                        }

                        Text("Audio Practice")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Ready to record")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    vm.toggleRecording(lang: lang, date: date, category: category, index: index) { dur in
                        onDurationChange?(dur)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: vm.isRecording ? "square.fill" : "mic.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(vm.isRecording ? "Stop" : (initialDuration > 0 || vm.currentDuration > 0 ? "Re-record" : "Record"))
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(vm.isRecording ? Color.red : accentColor.opacity(0.15))
                    .foregroundStyle(vm.isRecording ? .white : accentColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(AudioSquishButtonStyle())
            }

            if vm.isRecording {
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 3, height: max(4, vm.audioLevels[i] * 30))
                    }
                }
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .transition(.opacity)
            } else if vm.isPlaying {
                ProgressView(value: vm.elapsedPlayback, total: max(1.0, vm.currentDuration > 0 ? vm.currentDuration : initialDuration))
                    .tint(accentColor)
                    .frame(height: 4)
            }
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemFill).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.impact(weight: .medium), trigger: vm.isRecording)
        .sensoryFeedback(.selection, trigger: vm.isPlaying)
        .onDisappear {
            vm.teardown()
        }
    }

    private func formatTime(_ s: Double) -> String {
        let mins = Int(s) / 60
        let secs = Int(s) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct AudioSquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}