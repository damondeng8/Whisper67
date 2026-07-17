import Foundation
import CoreGraphics

/// Wispr Flow–style visualizer: center-tall bars, energy spreads outward as you speak louder.
/// Driven by overall mic loudness (not raw chaotic time-slices).
enum WaveformShaper {
    
    /// Map mic units → visual energy. ~2× more sensitive than the prior gate.
    static func gateAndCompress(_ raw: Float) -> CGFloat {
        // Lower floor so normal speech moves bars more (still ignores dead silence)
        let noiseFloor: Float = 0.05
        let gated = max(0, (raw - noiseFloor) / (1 - noiseFloor))
        // Milder compression (~2× effective gain vs gamma 1.45)
        let boosted = min(1.0, Double(gated) * 2.0)
        let compressed = pow(boosted, 1.15)
        return CGFloat(min(1, compressed))
    }
    
    /// Build bar heights 0…1 for `count` bars from a single loudness + optional band texture.
    static func bars(
        energy: CGFloat,
        count: Int,
        phase: Double,
        bandTexture: [Float] = []
    ) -> [CGFloat] {
        guard count > 0 else { return [] }
        
        // Idle: soft center “breathing” only
        let idleBreath = 0.10 + 0.04 * CGFloat(sin(phase * 0.9))
        let e = max(0, min(1, energy))
        
        // How far energy reaches toward the edges (0 = center only, 1 = full width)
        let spread = pow(e, 0.85)
        
        var out = [CGFloat](repeating: 0, count: count)
        let mid = Double(count - 1) / 2.0
        
        for i in 0..<count {
            // Distance from center 0…1
            let x = (Double(i) - mid) / mid   // -1…1
            let absX = abs(x)
            
            // Center envelope — always tallest in the middle
            let centerEnv = exp(-absX * absX * 2.8)           // gaussian
            let cosEnv = cos(absX * .pi / 2)                   // soft dome
            let envelope = centerEnv * 0.65 + cosEnv * 0.35
            
            // Outer bars need more volume to rise (spread from middle outward)
            let outerNeed = absX                          // 0 center → 1 edge
            let reach = max(0, spread - outerNeed * 0.72)
            let outerGain = pow(reach, 0.7)
            
            // Subtle organic motion (not random noise) — locked to phase + position
            let wobble = sin(phase * 2.1 + Double(i) * 0.55) * 0.06
                + sin(phase * 3.4 + Double(i) * 1.1) * 0.03
            let liveWobble = CGFloat(wobble) * e
            
            // Optional mild texture from real bands (doesn't dominate shape)
            var texture: CGFloat = 0
            if !bandTexture.isEmpty {
                let src = min(bandTexture.count - 1, i * bandTexture.count / count)
                texture = CGFloat(bandTexture[src]) * 0.12 * e
            }
            
            // Compose: idle center pulse + speech-driven dome + outer bloom
            let speechHeight =
                envelope * (0.18 + e * 0.82)   // middle grows with energy
                + outerGain * e * 0.55         // sides fill in when loud
                + liveWobble
                + texture
            
            let idleHeight = envelope * idleBreath * (1 - e * 0.85)
            
            let h = idleHeight + speechHeight
            // Soft floor / ceiling — never flat zero, never clipped harsh
            out[i] = max(0.06, min(1.0, h))
        }
        
        // Normalize so peak sits near energy (prevents over-sensitivity stacking)
        if let peak = out.max(), peak > 0.001 {
            let targetPeak = 0.14 + e * 0.86
            let scale = targetPeak / peak
            // Only pull down if too hot — keep dynamics when quieter
            if scale < 1 {
                for i in out.indices { out[i] *= scale }
            }
        }
        
        return out
    }
    
    /// Smooth lerp toward targets (attack vs release).
    static func smooth(
        current: [CGFloat],
        target: [CGFloat],
        attack: CGFloat = 0.38,
        release: CGFloat = 0.16
    ) -> [CGFloat] {
        let n = min(current.count, target.count)
        var next = current
        if next.count != target.count {
            next = target
            return next
        }
        for i in 0..<n {
            let a = target[i] > current[i] ? attack : release
            next[i] = current[i] + (target[i] - current[i]) * a
        }
        return next
    }
}
