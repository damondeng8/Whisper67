import SwiftUI
import Darwin

struct PerformanceTab: View {
    @State private var enableGPUAcceleration = true
    @State private var enableRealTimeProcessing = true
    @State private var maxMemoryUsage: Double = 2.0
    @State private var processingThreads: Double = 4.0
    @State private var cacheSize: Double = 500.0
    @State private var enableOptimizations = true
    @State private var enableBackgroundProcessing = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Performance")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Optimize Whisper67 for your hardware and usage patterns")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // System Info Card
                GlassCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "cpu")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.orange)
                            
                            Text("System Information")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(spacing: 12) {
                            SystemInfoRow(label: "Chip", value: getSystemChip(), isHighlighted: true)
                            SystemInfoRow(label: "Memory", value: getSystemMemory())
                            SystemInfoRow(label: "GPU Cores", value: getGPUCores())
                            SystemInfoRow(label: "Neural Engine", value: getNeuralEngine())
                            SystemInfoRow(label: "CPU Cores", value: getCPUCores())
                            
                            // Performance indicator
                            HStack {
                                Text("Performance Score")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    ForEach(0..<5) { index in
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(index < 4 ? .yellow : .gray.opacity(0.3))
                                    }
                                }
                                
                                Text("Excellent")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
                
                // Processing Settings
                GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "gearshape.2")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.blue)
                            
                            Text("Processing Settings")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Status indicator
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(enableGPUAcceleration ? .green : .orange)
                                    .frame(width: 6, height: 6)
                                
                                Text(enableGPUAcceleration ? "Optimized" : "Basic")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Core Performance Settings
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Core Performance")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 14) {
                                GlassToggle(
                                    "GPU Acceleration (Metal)",
                                    subtitle: "Use Apple Silicon's GPU for faster processing",
                                    isOn: $enableGPUAcceleration
                                )
                                
                                GlassToggle(
                                    "Neural Engine Optimization",
                                    subtitle: "Leverage specialized AI hardware for maximum speed",
                                    isOn: $enableOptimizations
                                )
                            }
                        }
                        
                        Divider()
                            .background(.ultraThinMaterial)
                        
                        // Processing Modes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Processing Modes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 14) {
                                GlassToggle(
                                    "Real-time Processing",
                                    subtitle: "Process audio as it's being recorded",
                                    isOn: $enableRealTimeProcessing
                                )
                                
                                GlassToggle(
                                    "Background Processing",
                                    subtitle: "Continue processing when app is not in focus",
                                    isOn: $enableBackgroundProcessing
                                )
                            }
                        }
                    }
                    .padding(20)
                }
                
                // Resource Limits
                GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "speedometer")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.green)
                            
                            Text("Resource Limits")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(spacing: 20) {
                            GlassSlider(
                                "Maximum Memory Usage",
                                value: $maxMemoryUsage,
                                in: 0.5...8.0,
                                step: 0.5
                            )
                            
                            GlassSlider(
                                "Processing Threads",
                                value: $processingThreads,
                                in: 1.0...8.0,
                                step: 1.0
                            )
                            
                            GlassSlider(
                                "Model Cache Size (MB)",
                                value: $cacheSize,
                                in: 100.0...2000.0,
                                step: 100.0
                            )
                            
                            // Resource usage indicator
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Resource Usage")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 16) {
                                    ResourceMeter(
                                        label: "CPU",
                                        value: 0.25,
                                        color: .blue
                                    )
                                    
                                    ResourceMeter(
                                        label: "Memory",
                                        value: 0.4,
                                        color: .green
                                    )
                                    
                                    ResourceMeter(
                                        label: "GPU",
                                        value: 0.15,
                                        color: .purple
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                
                // Performance Profiles
                GlassCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.purple)
                            
                            Text("Performance Profiles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(spacing: 12) {
                            PerformanceProfile(
                                title: "Battery Saver",
                                description: "Optimize for longer battery life",
                                icon: "battery.100",
                                isSelected: false
                            ) {
                                applyBatterySaverProfile()
                            }
                            
                            PerformanceProfile(
                                title: "Balanced",
                                description: "Good balance of speed and efficiency",
                                icon: "scale.3d",
                                isSelected: true
                            ) {
                                applyBalancedProfile()
                            }
                            
                            PerformanceProfile(
                                title: "Maximum Performance",
                                description: "Best quality and speed, higher power usage",
                                icon: "bolt.circle",
                                isSelected: false
                            ) {
                                applyMaxPerformanceProfile()
                            }
                        }
                    }
                    .padding(20)
                }
                
                // Quick Actions
                HStack(spacing: 12) {
                    GlassButton(
                        "Benchmark System",
                        icon: "speedometer",
                        style: .primary
                    ) {
                        // Run performance benchmark
                    }
                    
                    GlassButton(
                        "Clear Cache",
                        icon: "trash.circle",
                        style: .secondary
                    ) {
                        // Clear model cache
                    }
                    
                    GlassButton(
                        "Reset to Defaults",
                        icon: "arrow.clockwise",
                        style: .secondary
                    ) {
                        resetToDefaults()
                    }
                }
            }
            .padding(24)
        }
        .background {
            LinearGradient(
                colors: [
                    Color.green.opacity(0.05),
                    Color.orange.opacity(0.02),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private func applyBatterySaverProfile() {
        enableGPUAcceleration = false
        enableRealTimeProcessing = false
        maxMemoryUsage = 1.0
        processingThreads = 2.0
        cacheSize = 200.0
        enableOptimizations = false
    }
    
    private func applyBalancedProfile() {
        enableGPUAcceleration = true
        enableRealTimeProcessing = true
        maxMemoryUsage = 2.0
        processingThreads = 4.0
        cacheSize = 500.0
        enableOptimizations = true
    }
    
    private func applyMaxPerformanceProfile() {
        enableGPUAcceleration = true
        enableRealTimeProcessing = true
        maxMemoryUsage = 4.0
        processingThreads = 8.0
        cacheSize = 1000.0
        enableOptimizations = true
    }
    
    private func resetToDefaults() {
        applyBalancedProfile()
        enableBackgroundProcessing = false
    }
    
    // System Information Functions
    private func getSystemChip() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
        let brand = String(cString: machine)
        
        // Simplify Apple Silicon names
        if brand.contains("Apple") {
            return brand.components(separatedBy: " ").prefix(3).joined(separator: " ")
        }
        return brand
    }
    
    private func getSystemMemory() -> String {
        var size = 0
        sysctlbyname("hw.memsize", nil, &size, nil, 0)
        var memsize: UInt64 = 0
        sysctlbyname("hw.memsize", &memsize, &size, nil, 0)
        
        let gb = Double(memsize) / (1024 * 1024 * 1024)
        return String(format: "%.0f GB", gb)
    }
    
    private func getGPUCores() -> String {
        // Simplified - in a real app you'd query Metal device
        return "32 cores"
    }
    
    private func getNeuralEngine() -> String {
        return "16-core"
    }
    
    private func getCPUCores() -> String {
        var size = 0
        var cpuCount: Int32 = 0
        size = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &cpuCount, &size, nil, 0)
        
        return "\(cpuCount) cores"
    }
}

struct SystemInfoRow: View {
    let label: String
    let value: String
    let isHighlighted: Bool
    
    init(label: String, value: String, isHighlighted: Bool = false) {
        self.label = label
        self.value = value
        self.isHighlighted = isHighlighted
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                if isHighlighted {
                    Image(systemName: "cpu")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                }
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isHighlighted ? .orange : .secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.orange.opacity(0.1))
                    }
                }
        }
        .padding(.vertical, 2)
    }
}

struct ResourceMeter: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.ultraThinMaterial)
                    .frame(width: 20, height: 40)
                    .opacity(0.6)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.gradient)
                    .frame(width: 20, height: 40 * value)
            }
            
            Text("\(Int(value * 100))%")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct PerformanceProfile: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(description)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
        }
        .buttonStyle(PlainButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? .blue.opacity(0.1) : .clear)
                .overlay {
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .opacity(0.6)
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.blue.opacity(0.3), lineWidth: 1)
                    }
                }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}