import Foundation
import Speech
import AVFoundation

// Simpler POC that tests what we can without full entitlements

@main
struct TranscribePOC {
    static func main() {
        print("=== TranscribePOC: Testing macOS Speech APIs ===")
        print("macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("")

        // Test 1: Check if SFSpeechRecognizer is available
        print("1. SFSpeechRecognizer availability...")
        if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) {
            print("   ✓ SFSpeechRecognizer created")
            print("   - isAvailable: \(recognizer.isAvailable)")
            print("   - supportsOnDeviceRecognition: \(recognizer.supportsOnDeviceRecognition)")
        } else {
            print("   ✗ Failed to create SFSpeechRecognizer")
        }

        // Test 2: Check authorization status (without requesting)
        print("")
        print("2. Authorization status (current, not requesting)...")
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        print("   Speech Recognition: \(speechStatus.rawValue) ", terminator: "")
        switch speechStatus {
        case .authorized: print("(authorized)")
        case .denied: print("(denied)")
        case .restricted: print("(restricted)")
        case .notDetermined: print("(not determined - will prompt on first use)")
        @unknown default: print("(unknown)")
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("   Microphone: \(micStatus.rawValue) ", terminator: "")
        switch micStatus {
        case .authorized: print("(authorized)")
        case .denied: print("(denied)")
        case .restricted: print("(restricted)")
        case .notDetermined: print("(not determined - will prompt on first use)")
        @unknown default: print("(unknown)")
        }

        // Test 3: Check AVAudioEngine
        print("")
        print("3. AVAudioEngine...")
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        print("   ✓ AVAudioEngine created")
        print("   - Input sample rate: \(format.sampleRate) Hz")
        print("   - Input channels: \(format.channelCount)")

        // Test 4: Check ScreenCaptureKit availability
        print("")
        print("4. ScreenCaptureKit...")
        if #available(macOS 12.3, *) {
            print("   ✓ ScreenCaptureKit available (macOS 12.3+)")
            print("   Note: Requires Screen Recording permission to capture system audio")
        } else {
            print("   ✗ ScreenCaptureKit requires macOS 12.3+")
        }

        print("")
        print("=== Summary ===")
        print("To test full transcription, you need to:")
        print("1. Create an Xcode project (macOS App)")
        print("2. Add entitlements:")
        print("   - com.apple.security.device.audio-input (Microphone)")
        print("   - com.apple.security.personal-information.speech-recognition")
        print("3. Add to Info.plist:")
        print("   - NSSpeechRecognitionUsageDescription")
        print("   - NSMicrophoneUsageDescription")
        print("4. For system audio: Enable Screen Recording permission")
        print("")
        print("See: native/README.md for Xcode project setup instructions")
    }
}
