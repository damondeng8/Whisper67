import Foundation
import AVFoundation
import Observation

@Observable
class AudioDeviceService {
    var availableMicrophones: [AudioDevice] = []
    var selectedMicrophone: AudioDevice?
    var isLoading = true
    
    struct AudioDevice: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let deviceID: String
        let isDefault: Bool
        
        var displayName: String {
            isDefault ? "\(name) (Default)" : name
        }
    }
    
    init() {
        loadAudioDevices()
    }
    
    func loadAudioDevices() {
        Task {
            await discoverAudioDevices()
        }
    }
    
    @MainActor
    private func discoverAudioDevices() async {
        isLoading = true
        
        // For macOS, we'll use a simplified approach since AVAudioSession is iOS-only
        var devices: [AudioDevice] = []
        
        // Add default device first
        devices.append(AudioDevice(
            name: "System Default",
            deviceID: "default",
            isDefault: true
        ))
        
        // Add common macOS devices
        devices.append(AudioDevice(
            name: "Built-in Microphone",
            deviceID: "builtin",
            isDefault: false
        ))
        
        // Check if we can enumerate actual devices using Core Audio
        if let discoveredDevices = enumerateAudioDevices() {
            devices.append(contentsOf: discoveredDevices)
        }
        
        availableMicrophones = devices
        selectedMicrophone = devices.first
        isLoading = false
    }
    
    private func enumerateAudioDevices() -> [AudioDevice]? {
        // This is a simplified version - in a real app you'd use AudioObjectGetPropertyData
        // to enumerate actual Core Audio devices
        return [
            AudioDevice(name: "External Microphone", deviceID: "external", isDefault: false),
            AudioDevice(name: "USB Audio Device", deviceID: "usb", isDefault: false)
        ]
    }
    
    func selectMicrophone(_ device: AudioDevice) {
        selectedMicrophone = device
        // Here you would configure the actual audio input
        print("Selected microphone: \(device.displayName)")
    }
    
    func refreshDevices() {
        loadAudioDevices()
    }
}
