import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FreeFlowCore

private struct LinuxContext: ContextSummaryProviding {
    let contextSummary: String
}

private struct VoiceMacroRule {
    let command: String
    let payload: String
}

private enum LinuxAppError: LocalizedError {
    case missingValue(String)
    case missingRequiredOption(String)
    case unknownOption(String)
    case unsupportedRecording
    case invalidRecordSeconds(String)
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "Missing value for option \(option)"
        case .missingRequiredOption(let option):
            return "Missing required option \(option)"
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .unsupportedRecording:
            return """
            Microphone recording requires `arecord` to be installed.
            Use --audio-file /path/to/file.wav as a fallback.
            """
        case .invalidRecordSeconds(let value):
            return "--record-seconds expects a positive integer, got: \(value)"
        case .recordingFailed(let details):
            return "Microphone recording failed: \(details)"
        }
    }
}

private struct LinuxCLIConfig {
    var audioFilePath: String?
    var interactive = false
    var recordSeconds: Int?
    var baseURL = "https://api.groq.com/openai/v1"
    var apiKey: String?
    var transcriptionBaseURL: String?
    var transcriptionAPIKey: String?
    var transcriptionModel = "whisper-large-v3"
    var transcriptionLanguage: String?
    var postProcessingModel = ""
    var postProcessingFallbackModel = ""
    var customVocabulary = ""
    var outputLanguage = ""
    var contextSummary = "Dictating from FreeFlow Linux terminal frontend."
    var skipPostProcessing = false
    var voiceMacros: [VoiceMacroRule] = []
}

@main
struct FreeFlowLinuxApp {
    static func main() async {
        do {
            let config = try parseArguments(CommandLine.arguments.dropFirst())
            try await run(config: config)
        } catch {
            printError("Error: \(error.localizedDescription)")
            if CommandLine.arguments.contains("--help") == false {
                printError("")
                printError(usageText)
            }
            exit(1)
        }
    }

    private static func run(config: LinuxCLIConfig) async throws {
        let apiKey = (config.apiKey ?? ProcessInfo.processInfo.environment["FREEFLOW_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw LinuxAppError.missingRequiredOption("--api-key or FREEFLOW_API_KEY")
        }

        var audioURL: URL
        if let audioFilePath = config.audioFilePath {
            audioURL = URL(fileURLWithPath: audioFilePath)
        } else {
            let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            audioURL = temporaryDirectory.appendingPathComponent("freeflow-linux-\(UUID().uuidString).wav")
            if config.interactive {
                try recordInteractively(to: audioURL)
            } else if let recordSeconds = config.recordSeconds {
                try recordFixedDuration(seconds: recordSeconds, to: audioURL)
            } else {
                throw LinuxAppError.missingRequiredOption("--audio-file, --interactive, or --record-seconds")
            }
        }

        let transcriptionService = try TranscriptionService(
            apiKey: resolvedTranscriptionAPIKey(from: config, fallbackKey: apiKey),
            baseURL: config.transcriptionBaseURL ?? config.baseURL,
            transcriptionModel: config.transcriptionModel,
            language: config.transcriptionLanguage
        )
        let rawTranscript = try await transcriptionService.transcribe(fileURL: audioURL)
        let finalTranscript: String
        if config.skipPostProcessing {
            finalTranscript = applyVoiceMacros(config.voiceMacros, to: rawTranscript)
        } else {
            let postProcessingService = PostProcessingService(
                apiKey: apiKey,
                baseURL: config.baseURL,
                preferredModel: config.postProcessingModel,
                preferredFallbackModel: config.postProcessingFallbackModel
            )
            let result = try await postProcessingService.postProcess(
                transcript: rawTranscript,
                context: LinuxContext(contextSummary: config.contextSummary),
                customVocabulary: config.customVocabulary,
                outputLanguage: config.outputLanguage
            )
            finalTranscript = applyVoiceMacros(config.voiceMacros, to: result.transcript)
        }

        print(finalTranscript)
    }

    private static func resolvedTranscriptionAPIKey(from config: LinuxCLIConfig, fallbackKey: String) -> String {
        let provided = config.transcriptionAPIKey ?? ProcessInfo.processInfo.environment["FREEFLOW_TRANSCRIPTION_API_KEY"]
        let trimmed = (provided ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackKey : trimmed
    }

    private static func parseArguments<S: Sequence>(_ arguments: S) throws -> LinuxCLIConfig where S.Element == String {
        var config = LinuxCLIConfig()
        var iterator = arguments.makeIterator()

        func nextValue(for option: String) throws -> String {
            guard let value = iterator.next() else {
                throw LinuxAppError.missingValue(option)
            }
            return value
        }

        while let argument = iterator.next() {
            switch argument {
            case "--help", "-h":
                print(usageText)
                exit(0)
            case "--audio-file":
                config.audioFilePath = try nextValue(for: argument)
            case "--interactive":
                config.interactive = true
            case "--record-seconds":
                let value = try nextValue(for: argument)
                guard let seconds = Int(value), seconds > 0 else {
                    throw LinuxAppError.invalidRecordSeconds(value)
                }
                config.recordSeconds = seconds
            case "--api-key":
                config.apiKey = try nextValue(for: argument)
            case "--base-url":
                config.baseURL = try nextValue(for: argument)
            case "--transcription-base-url":
                config.transcriptionBaseURL = try nextValue(for: argument)
            case "--transcription-api-key":
                config.transcriptionAPIKey = try nextValue(for: argument)
            case "--transcription-model":
                config.transcriptionModel = try nextValue(for: argument)
            case "--language":
                config.transcriptionLanguage = try nextValue(for: argument)
            case "--post-processing-model":
                config.postProcessingModel = try nextValue(for: argument)
            case "--post-processing-fallback-model":
                config.postProcessingFallbackModel = try nextValue(for: argument)
            case "--custom-vocabulary":
                config.customVocabulary = try nextValue(for: argument)
            case "--output-language":
                config.outputLanguage = try nextValue(for: argument)
            case "--context-summary":
                config.contextSummary = try nextValue(for: argument)
            case "--voice-macro":
                let value = try nextValue(for: argument)
                guard let separator = value.firstIndex(of: "=") else {
                    throw LinuxAppError.missingValue("\(argument) command=payload")
                }
                let command = String(value[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let payload = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                config.voiceMacros.append(VoiceMacroRule(command: command, payload: payload))
            case "--skip-post-processing":
                config.skipPostProcessing = true
            default:
                throw LinuxAppError.unknownOption(argument)
            }
        }

        return config
    }

    private static func recordFixedDuration(seconds: Int, to outputURL: URL) throws {
        let recording = try makeRecordingProcess(outputURL: outputURL, durationSeconds: seconds)
        try recording.process.run()
        recording.process.waitUntilExit()
        try verifyRecordingExit(recording)
    }

    private static func recordInteractively(to outputURL: URL) throws {
        print("Press Enter to start recording...")
        _ = readLine()
        let recording = try makeRecordingProcess(outputURL: outputURL, durationSeconds: nil)
        try recording.process.run()
        print("Recording. Press Enter to stop...")
        _ = readLine()
        recording.process.terminate()
        recording.process.waitUntilExit()
        try verifyRecordingExit(recording)
    }

    private static func makeRecordingProcess(outputURL: URL, durationSeconds: Int?) throws -> (process: Process, stderr: Pipe) {
        let executablePath = "/usr/bin/env"
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LinuxAppError.unsupportedRecording
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        let stderrPipe = Pipe()
        var arguments = ["arecord", "-f", "S16_LE", "-r", "16000", "-c", "1"]
        if let durationSeconds {
            arguments += ["-d", String(durationSeconds)]
        }
        arguments.append(outputURL.path)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = stderrPipe
        return (process, stderrPipe)
    }

    private static func verifyRecordingExit(_ recording: (process: Process, stderr: Pipe)) throws {
        guard recording.process.terminationStatus == 0 else {
            let data = recording.stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let details = if let message, !message.isEmpty {
                message
            } else {
                "arecord exited with status \(recording.process.terminationStatus)"
            }
            throw LinuxAppError.recordingFailed(details)
        }
    }

    private static func applyVoiceMacros(_ macros: [VoiceMacroRule], to transcript: String) -> String {
        macros.reduce(transcript) { partialResult, macro in
            guard !macro.command.isEmpty else { return partialResult }
            return partialResult.replacingOccurrences(
                of: macro.command,
                with: macro.payload,
                options: [.caseInsensitive]
            )
        }
    }

    private static var usageText: String {
        """
        FreeFlow Linux frontend (terminal fallback)

        Usage:
          freeflow-linux --audio-file /path/to/audio.wav [options]
          freeflow-linux --record-seconds 8 [options]
          freeflow-linux --interactive [options]

        Required:
          --api-key <key>                  or set FREEFLOW_API_KEY

        Options:
          --base-url <url>                 OpenAI-compatible API base URL
          --transcription-base-url <url>   Optional dedicated transcription API URL
          --transcription-api-key <key>    Optional dedicated transcription key
          --transcription-model <id>
          --language <code>                Transcription language (e.g., en)
          --post-processing-model <id>
          --post-processing-fallback-model <id>
          --custom-vocabulary <text>
          --voice-macro command=payload    Repeatable replacement rule (applied in order)
          --context-summary <text>         Linux fallback for nearby-app context
          --output-language <language>
          --skip-post-processing
          --help
        """
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
