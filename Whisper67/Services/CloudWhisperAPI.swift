import Foundation
import AVFoundation

/// OpenAI-compatible Whisper transcription client for OpenAI and Groq.
enum CloudWhisperAPI {
    
    /// Session for Whisper STT — no artificial deadline; long dictations may take a while.
    /// (0 = system default unlimited for request/resource on URLSessionConfiguration)
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // No cap: let Whisper finish long audio / slow networks.
        config.timeoutIntervalForRequest = 0
        config.timeoutIntervalForResource = 0
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    
    struct TranscriptionResult {
        let text: String
        let durationSeconds: Double
    }
    
    enum APIError: LocalizedError {
        case missingAPIKey
        case invalidAudio
        case httpStatus(Int, String)
        case emptyResponse
        case network(Error)
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Add an API key in Settings → API"
            case .invalidAudio:
                return "Could not read recorded audio"
            case .httpStatus(let code, let body):
                return "API error \(code): \(body)"
            case .emptyResponse:
                return "Empty transcription from API"
            case .network(let error):
                return error.localizedDescription
            }
        }
    }
    
    static func transcribe(
        audioURL: URL,
        provider: TranscriptionProvider,
        apiKey: String,
        language: String,
        prompt: String
    ) async throws -> TranscriptionResult {
        guard provider.isCloud else {
            throw APIError.missingAPIKey
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw APIError.missingAPIKey }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw APIError.invalidAudio
        }
        
        let duration = (try? audioDuration(url: audioURL)) ?? 0
        
        let endpoint: URL
        let model: String
        switch provider {
        case .openAI:
            endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
            model = "whisper-1"
        case .groq:
            endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
            model = "whisper-large-v3-turbo"
        case .local:
            throw APIError.missingAPIKey
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // No request timeout — transcription can take as long as the provider needs
        request.timeoutInterval = .infinity
        
        let audioData = try Data(contentsOf: audioURL)
        let filename = audioURL.lastPathComponent
        let mime = mimeType(for: audioURL)
        
        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField(name: "model", value: model)
        appendField(name: "response_format", value: "json")
        if language != "auto" && !language.isEmpty {
            appendField(name: "language", value: language)
        }
        if !prompt.isEmpty {
            appendField(name: "prompt", value: prompt)
        }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.emptyResponse
            }
            
            if http.statusCode < 200 || http.statusCode >= 300 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                // Prefer API error message when present
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let msg = error["message"] as? String {
                    throw APIError.httpStatus(http.statusCode, msg)
                }
                throw APIError.httpStatus(http.statusCode, message.prefix(200).description)
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                throw APIError.emptyResponse
            }
            
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return TranscriptionResult(text: "No speech detected", durationSeconds: duration)
            }
            
            return TranscriptionResult(text: trimmed, durationSeconds: duration)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }
    
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/m4a"
        case "webm": return "audio/webm"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        default: return "application/octet-stream"
        }
    }
    
    private static func audioDuration(url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
