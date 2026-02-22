//
//  ContentView.swift
//  Translator
//
//  Created by Yubo Rao on 3/7/24.
//

import SwiftUI
import OpenAI
import AVFoundation

class AudioRecorder: NSObject, ObservableObject {
    var audioRecorder: AVAudioRecorder?
    var audioURL: URL?

    func startRecording() {
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")
        print("📂 File Path: \(audioURL!.path)")
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioURL!, settings: settings)
            audioRecorder?.record()
        } catch {
            print("Record error: \(error)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
    }
}

class RecordManager: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = "Your text will appear here..."
    @Published var isTranscribing = false
    
    private let recorder = AudioRecorder() // Your AVAudioRecorder helper
    private let openAI = OpenAI(apiToken: "OpenAI Key")

    func toggleRecording() {
        if isRecording {
            // 1. Stop Recording
            print("Stop Recording")
            recorder.stopRecording()
            isRecording = false
            
            // 2. Start Transcription
            if let url = recorder.audioURL {
                Task {
                    await transcribeWithSDK(url: url)
                }
            }
        } else {
            // Start Recording
            print("Start Recording")
            recorder.startRecording()
            isRecording = true
        }
    }

    @MainActor
    private func transcribeWithSDK(url: URL) async {
        isTranscribing = true
        
        do {
            let audioData = try Data(contentsOf: url)
            print("📂 Sending file: \(url.lastPathComponent)")
            print("📊 File size: \(audioData.count) bytes")
    
            let query = AudioTranscriptionQuery(
                file: audioData,
                fileType: .m4a,
                model: .whisper_1
            )
            
            let result = try await openAI.audioTranscriptions(query: query)
            self.transcribedText = result.text
        } catch {
            self.transcribedText = "Error: \(error.localizedDescription)"
        }
        
        isTranscribing = false
    }
}

class TranslationViewModel: ObservableObject {
    @Published var translatedText = ""
    @Published var isProcessing = false
    
    private let openAI = OpenAI(apiToken: "OpenAI Key")

    func translate(_ text: String, to targetLanguage: String) async {
        guard !text.isEmpty else { return }
        
        await MainActor.run { isProcessing = true }

        // Setup the translator prompt
        let query = ChatQuery(
            messages: [
                .init(role: .system, content: "You are a professional translator. Translate the following text to \(targetLanguage). Return ONLY the translation.")!,
                .init(role: .user, content: text)!
            ],
            model: .gpt4_o_mini,
            temperature: 0.2
        )

        do {
            let result = try await openAI.chats(query: query)
            await MainActor.run {
                self.translatedText = result.choices.first?.message.content ?? ""
                self.isProcessing = false
            }
        } catch {
            print("Translation Error: \(error.localizedDescription)")
            await MainActor.run { isProcessing = false }
        }
    }
}

class SpeechManager {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, languageCode: String) {
        // Stop any current speech before starting new one
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        
        // Set the voice (e.g., "es-ES" for Spanish, "fr-FR" for French)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        
        // Optional: Adjust speed and pitch
        utterance.rate = 0.5 // Range 0.0 to 1.0
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }
}



struct ContentView: View {
    @StateObject private var recordManager = RecordManager()
    @StateObject private var vm = TranslationViewModel()
        @State private var inputText = ""
        @State private var selectedLanguage = "English"
        
        let languages = ["English", "Chinese", "Spanish", "Japanese", "Korean", "French"]
    
    func getLanguageCode(for name: String) -> String {
        let mapping = [
            "Spanish": "es-ES",
            "French": "fr-FR",
            "Japanese": "ja-JP",
            "Korean": "ko-KR",
            "Chinese": "zh-CN"
        ]
        return mapping[name] ?? "en-US"
    }

        var body: some View {
            NavigationStack {
                VStack(spacing: 20) {
                    // Language Picker
                    Picker("Target Language", selection: $selectedLanguage) {
                                    ForEach(languages, id: \.self) {
                                        Text($0)
                                    }
                                }
                                .pickerStyle(.menu) // This makes it a dropdown menu
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                    // Recording Button
                                Text(recordManager.isRecording ? "Listening..." : "Tap to Speak")
                                    .font(.headline)
                                    .foregroundColor(recordManager.isRecording ? .red : .primary)

                                Button(action: {
                                    withAnimation(.spring()) {
                                        recordManager.toggleRecording()
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(recordManager.isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.1))
                                            .frame(width: 90, height: 90)
                                        
                                        Circle()
                                            .fill(recordManager.isRecording ? Color.red : Color.blue)
                                            .frame(width: 70, height: 70)
                                            .shadow(radius: recordManager.isRecording ? 10 : 0)
                                        
                                        Image(systemName: recordManager.isRecording ? "stop.fill" : "mic.fill")
                                            .font(.system(size: 30, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .scaleEffect(recordManager.isRecording ? 1.1 : 1.0)
                    // Input Area
                    TextEditor(text: $inputText)
                        .frame(height: 150)
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                        .padding(.horizontal)
                        
                    // Action Button
                    Button(action: {
                        Task { await vm.translate(inputText, to: selectedLanguage) }
                    }) {
                        if vm.isProcessing {
                            ProgressView().tint(.white)
                        } else {
                            Text("Translate")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .disabled(inputText.isEmpty || vm.isProcessing)

                    // Result Area
                    if !vm.translatedText.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Result:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(vm.translatedText)
                                .font(.title3)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(10)
                                .contextMenu {
                                    Button("Copy") {
                                        UIPasteboard.general.string = vm.translatedText
                                    }
                                }
                        }
                        .padding(.horizontal)
                        .transition(.opacity)
                    }
                    
                    Spacer()
                    
                    //Text to speech
                    Section("Translation") {
                        Text(vm.translatedText)
                        
                        Button(action: {
                            // Map your selectedLanguage to the code
                            let code = getLanguageCode(for: selectedLanguage)
                            SpeechManager.shared.speak(vm.translatedText, languageCode: code)
                        }) {
                            Label("Listen", systemImage: "speaker.wave.2.fill")
                        }
                        .disabled(vm.translatedText.isEmpty)
                    }
                }
                .onChange(of: recordManager.transcribedText) {
                    self.inputText = recordManager.transcribedText
                }
                .navigationTitle("Translator")
                .navigationBarTitleDisplayMode(.inline)
                .animation(.default, value: vm.translatedText)
                .contentShape(Rectangle())
                .onTapGesture {
                            hideKeyboard()
                        }
            }
        }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


#Preview {
    ContentView()
}
