import SwiftUI

struct ConfettiView: View {
    private struct Particle: Identifiable {
        let id = UUID()
        let originX: CGFloat
        let originY: CGFloat
        let color: Color
        let size: CGSize
        let rotation: Double
        let speed: CGFloat
        let drift: CGFloat
        let spin: Double
        let delay: TimeInterval
    }

    @State private var particles: [Particle] = []
    @State private var startDate = Date()
    @State private var isAnimating = true

    private static let particleCount = 36
    private static let particleLifetime: TimeInterval = 2.4
    private static let delayStep: TimeInterval = 0.012
    private static let animationDuration = particleLifetime + (Double(particleCount - 1) * delayStep)

    private static let colors: [Color] = [
        .accentColor,
        .green,
        .orange,
        .pink,
        .yellow,
        .cyan
    ]

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let elapsed = timeline.date.timeIntervalSince(startDate)
                        let centerX = size.width / 2

                        for particle in particles {
                            let age = elapsed - particle.delay
                            guard age > 0, age < Self.particleLifetime else { continue }

                            let progress = age / Self.particleLifetime
                            let x = centerX + particle.originX + sin(age * 3.2) * particle.drift
                            let y = particle.originY + age * particle.speed
                            let angle = (particle.rotation + age * particle.spin) * .pi / 180

                            var particleContext = context
                            particleContext.opacity = 1 - progress
                            particleContext.translateBy(x: x, y: y)
                            particleContext.rotate(by: Angle(radians: angle))
                            let rect = CGRect(
                                x: -particle.size.width / 2,
                                y: -particle.size.height / 2,
                                width: particle.size.width,
                                height: particle.size.height
                            )
                            particleContext.fill(Path(rect), with: .color(particle.color))
                        }
                    }
                }
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startDate = .now
            particles = Self.makeParticles()
            isAnimating = true
        }
        .task(id: startDate) {
            try? await Task.sleep(for: .seconds(Self.animationDuration))
            guard !Task.isCancelled else { return }
            isAnimating = false
        }
    }

    private static func makeParticles() -> [Particle] {
        (0..<particleCount).map { index in
            Particle(
                originX: CGFloat.random(in: -140...140),
                originY: CGFloat.random(in: -24...8),
                color: colors.randomElement() ?? .accentColor,
                size: CGSize(width: CGFloat.random(in: 4...7), height: CGFloat.random(in: 6...10)),
                rotation: Double.random(in: 0...360),
                speed: CGFloat.random(in: 90...150),
                drift: CGFloat.random(in: 12...28),
                spin: Double.random(in: -220...220),
                delay: Double(index) * delayStep
            )
        }
    }
}
