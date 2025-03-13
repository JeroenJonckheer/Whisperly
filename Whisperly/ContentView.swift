import SwiftUI
import AVFoundation
import BackgroundTasks

class WhisperlyViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isPlaying = false
    @Published var timeRemaining: Int = 0
    @Published var currentAffirmation: String? = nil
    private var speechSynthesizer = AVSpeechSynthesizer()
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var affirmations: [String] = []
    private var workItem: DispatchWorkItem?
    private var selectedVoice: AVSpeechSynthesisVoice?

    override init() {
        super.init()
        configureAudioSession()
        loadAffirmations()
        selectVoice()
        restoreTimer()
        speechSynthesizer.delegate = self
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
        } catch {
            print("❌ ERROR: Kan AudioSession niet activeren - \(error.localizedDescription)")
        }
    }

    private func selectVoice() {
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        if let voice = availableVoices.first(where: { $0.identifier == "com.apple.voice.en-US.Samantha" }) {
            selectedVoice = voice
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: "en-US") {
            selectedVoice = defaultVoice
        } else {
            selectedVoice = nil
        }
    }

    func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startAffirmationLoop()
        } else {
            speechSynthesizer.stopSpeaking(at: .immediate)
            workItem?.cancel()
            stopBackgroundTask()
            currentAffirmation = nil
        }
    }

    private func loadAffirmations() {
        if let url = Bundle.main.url(forResource: "affirmations", withExtension: "json") {
            print("✅ Affirmations file found at: \(url.path)")
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([String].self, from: data)
                affirmations = decoded
            } catch {
                print("❌ ERROR: Cannot load JSON data - \(error.localizedDescription)")
            }
        } else {
            print("❌ ERROR: affirmations.json not found in bundle!")
        }
    }

    private func startAffirmationLoop() {
        guard !affirmations.isEmpty else { return }

        let delay = Int.random(in: 5...10)
        print("⏳ New delay set to: \(delay) seconds")
        timeRemaining = delay
        UserDefaults.standard.set(Date().timeIntervalSince1970 + Double(delay), forKey: "nextAffirmationTime")

        registerBackgroundTask()

        workItem?.cancel()
        let newWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            for _ in 0..<self.timeRemaining {
                guard self.isPlaying else {
                    self.stopBackgroundTask()
                    return
                }
                Thread.sleep(forTimeInterval: 1)
                DispatchQueue.main.async {
                    if self.timeRemaining > 0 {
                        self.timeRemaining -= 1
                        UserDefaults.standard.set(Date().timeIntervalSince1970 + Double(self.timeRemaining), forKey: "nextAffirmationTime")
                    }
                }
            }
            DispatchQueue.main.async {
                if self.isPlaying {
                    self.speakAffirmation()
                } else {
                    self.stopBackgroundTask()
                }
            }
        }
        workItem = newWorkItem
        DispatchQueue.global(qos: .background).async(execute: newWorkItem)
    }

    func speakAffirmation() {
        guard let affirmation = affirmations.randomElement() else { return }
        currentAffirmation = affirmation
        print("🔊 Whispering with real energy: \(affirmation)")

        let randomEnding = ["!", "...", "?", ""].randomElement() ?? ""
        let utterance = AVSpeechUtterance(string: "\(affirmation)\(randomEnding)")
        utterance.voice = selectedVoice
        utterance.volume = Float(Double.random(in: 0.02...0.07))
        utterance.rate = Float(Double.random(in: 0.35...0.5))
        utterance.pitchMultiplier = Float(Double.random(in: 1.2...1.4))
        utterance.preUtteranceDelay = Double.random(in: 0.05...0.15)
        utterance.postUtteranceDelay = Double.random(in: 0.05...0.2)

        speechSynthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if isPlaying {
            startAffirmationLoop()
        }
    }

    private func registerBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.stopBackgroundTask()
        }
    }

    private func stopBackgroundTask() {
        workItem?.cancel()
        workItem = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            print("Background task ended")
        }
    }

    private func restoreTimer() {
        let nextTime = UserDefaults.standard.double(forKey: "nextAffirmationTime")
        let currentTime = Date().timeIntervalSince1970
        // Geen automatische start bij herstarten
        if nextTime > currentTime && !isPlaying {
            timeRemaining = Int(nextTime - currentTime)
            isPlaying = false // Zorg ervoor dat het niet automatisch start
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = WhisperlyViewModel()
    @State private var displayedAffirmation: String? = nil
    @State private var textOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // Achtergrondafbeelding
            Image("BackgroundImage")
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
                .opacity(0.9)

            // Affirmatie in de linkerbovenhoek
            if let affirmation = displayedAffirmation {
                Text(affirmation)
                    .font(.custom("Bradley Hand", size: 16))
                    .foregroundColor(Color(red: 0.4, green: 0.2, blue: 0.1))
                    .frame(maxWidth: 120, alignment: .leading)
                    .offset(x: -100, y: -150)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(8)
                    .opacity(textOpacity)
                    .shadow(color: Color(red: 0.4, green: 0.2, blue: 0.1).opacity(0.3), radius: 4, x: 2, y: 2)
            }

            // Play/Stop-knop, met vaste positie
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.togglePlayback()
                }
            }) {
                Image(viewModel.isPlaying ? "stop" : "play")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.2))
                    .frame(width: 70, height: 70)
                    .shadow(color: Color(red: 0.4, green: 0.2, blue: 0.1).opacity(0.3), radius: 4, x: 2, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 5, y: -25)

            // Notificatie (aantal seconden), links van de knop
            if viewModel.isPlaying {
                Text("\(viewModel.timeRemaining)")
                    .font(.custom("Bradley Hand", size: 16))
                    .foregroundColor(Color(red: 0.4, green: 0.2, blue: 0.1))
                    .shadow(color: Color(red: 0.5, green: 0.3, blue: 0.2).opacity(0.5), radius: 2, x: 1, y: 1) // Subtiele slagschaduw
                    .offset(x: -160, y: 0) // Jouw aangepaste positie
            }

            // "..."-knop onderaan, zonder kader
            Button(action: {
                viewModel.speakAffirmation()
            }) {
                Text("...")
                    .font(.title)
                    .foregroundColor(Color(red: 0.4, green: 0.2, blue: 0.1))
            }
        }
        .onChange(of: viewModel.currentAffirmation) { newAffirmation in
            print("Current affirmation changed to: \(newAffirmation ?? "nil")")
            withAnimation(.easeInOut(duration: 1.5)) {
                textOpacity = 0.0
                print("Fading out, opacity: \(textOpacity)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                displayedAffirmation = newAffirmation
                withAnimation(.easeInOut(duration: 1.5)) {
                    textOpacity = 1.0
                    print("Fading in, opacity: \(textOpacity)")
                }
            }
        }
        .onAppear {
            print("View appeared, currentAffirmation: \(viewModel.currentAffirmation ?? "nil")")
            // Geen automatische start, alleen handmatig via knop
            if let initialAffirmation = viewModel.currentAffirmation {
                displayedAffirmation = initialAffirmation
                withAnimation(.easeInOut(duration: 0.5)) {
                    textOpacity = 1.0
                    print("Initial fade-in, opacity: \(textOpacity)")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
