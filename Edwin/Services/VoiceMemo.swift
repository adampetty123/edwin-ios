import AVFoundation
import Foundation
import Speech

/// Records a voice memo and transcribes it on-device. The transcript is sent
/// to Edwin as a normal text message — no audio leaves the phone.
@MainActor
final class VoiceMemo: NSObject, ObservableObject {
    @Published var recording = false
    @Published var transcribing = false
    @Published var elapsed: TimeInterval = 0
    @Published var error: String?

    private var recorder: AVAudioRecorder?
    private var fileUrl: URL?
    private var timer: Timer?

    /// Ask for mic + speech permissions and start recording. False if denied.
    func start() async -> Bool {
        error = nil
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { error = "Mic access is off — enable it in Settings."; return false }
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else { error = "Speech recognition is off — enable it in Settings."; return false }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("memo-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            fileUrl = url
            recording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed += 1 }
            }
            return true
        } catch {
            self.error = "Couldn't start recording. Give it another go?"
            return false
        }
    }

    /// Stop and transcribe. Returns the transcript (nil if empty/failed).
    func stopAndTranscribe() async -> String? {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = fileUrl else { return nil }
        fileUrl = nil

        transcribing = true
        defer { transcribing = false }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Transcription isn't available right now."
            return nil
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        let transcript: String? = await withCheckedContinuation { cont in
            var finished = false
            recognizer.recognitionTask(with: request) { result, err in
                if finished { return }
                if let result, result.isFinal {
                    finished = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                } else if err != nil {
                    finished = true
                    cont.resume(returning: nil)
                }
            }
        }
        try? FileManager.default.removeItem(at: url)
        let clean = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean?.isEmpty != false { error = "Didn't catch that — try again a bit closer to the mic?" }
        return clean?.isEmpty == false ? clean : nil
    }

    /// Abandon an in-flight recording without transcribing.
    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        recording = false
        if let url = fileUrl { try? FileManager.default.removeItem(at: url) }
        fileUrl = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
