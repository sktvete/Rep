import AVFoundation
import Foundation

@MainActor
final class ExerciseStepSpeechService {
    static let shared = ExerciseStepSpeechService()

    /// Source (cloud voice): Microsoft Azure AI Speech Text-to-Speech.
    /// Voice name: `en-US-AvaNeural` (Neural voice family).
    /// Endpoint: `https://{region}.tts.speech.microsoft.com/cognitiveservices/v1`
    private static let azureVoiceName = "en-US-AvaNeural"
    private static let azureOutputFormat = "audio-24khz-160kbitrate-mono-mp3"

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?
    private var requestID = UUID()

    func speakStep(number: Int, text: String) {
        let sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = sanitized.isEmpty ? "\(number)." : "\(number). \(sanitized)"
        let currentRequestID = UUID()

        requestID = currentRequestID
        speechTask?.cancel()
        player?.stop()
        synthesizer.stopSpeaking(at: .immediate)

        guard azureCredentials != nil else {
            speakOnDevice(spoken)
            return
        }

        speechTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let audioData = try await synthesizeAzure(spoken)
                try Task.checkCancellation()
                guard requestID == currentRequestID else { return }
                try play(audioData)
            } catch is CancellationError {
                return
            } catch {
                guard requestID == currentRequestID else { return }
                speakOnDevice(spoken)
            }
        }
    }

    private var azureCredentials: (key: String, region: String)? {
        let env = ProcessInfo.processInfo.environment
        guard
            let key = env["AZURE_SPEECH_KEY"],
            let region = env["AZURE_SPEECH_REGION"],
            !key.isEmpty,
            !region.isEmpty
        else {
            return nil
        }
        return (key, region)
    }

    private func synthesizeAzure(_ text: String) async throws -> Data {
        guard let credentials = azureCredentials else {
            throw NSError(domain: "ExerciseStepSpeechService", code: 1)
        }

        let endpoint = URL(string: "https://\(credentials.region).tts.speech.microsoft.com/cognitiveservices/v1")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.azureOutputFormat, forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue(credentials.key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("Rep", forHTTPHeaderField: "User-Agent")
        request.httpBody = ssml(text: text).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "ExerciseStepSpeechService", code: 2)
        }
        return data
    }

    private func ssml(text: String) -> String {
        """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>
          <voice name='\(Self.azureVoiceName)'>\(escapeForXML(text))</voice>
        </speak>
        """
    }

    private func escapeForXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func play(_ data: Data) throws {
        try prepareAudioSession()
        player?.stop()
        player = try AVAudioPlayer(data: data)
        player?.prepareToPlay()
        player?.play()
    }

    private func speakOnDevice(_ text: String) {
        try? prepareAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredOnDeviceVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func preferredOnDeviceVoice() -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }

        return englishVoices
            .filter { $0.name.localizedCaseInsensitiveContains("Ava") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? englishVoices.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func prepareAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true)
    }
}
