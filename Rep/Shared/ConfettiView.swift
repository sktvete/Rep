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
        let shape: ShapeKind
    }

    private enum ShapeKind: CaseIterable {
        case rectangle
        case circle
        case ribbon
    }

    @State private var particles: [Particle] = []
    @State private var startDate = Date()
    @State private var isAnimating = true

    private static let particleCount = 140
    private static let particleLifetime: TimeInterval = 3.6
    private static let delayStep: TimeInterval = 0.008
    private static let animationDuration = particleLifetime + (Double(particleCount - 1) * delayStep)

    private static let colors: [Color] = [
        .accentColor,
        .green,
        .orange,
        .pink,
        .yellow,
        .cyan,
        .mint,
        .purple,
        .red,
        Color(red: 1, green: 0.84, blue: 0.2)
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
                            let x = centerX + particle.originX + sin(age * 3.6) * particle.drift
                            let y = particle.originY + age * particle.speed
                            let angle = (particle.rotation + age * particle.spin) * .pi / 180
                            let fade = progress < 0.75 ? 1 : max(0, 1 - (progress - 0.75) / 0.25)

                            var particleContext = context
                            particleContext.opacity = fade
                            particleContext.translateBy(x: x, y: y)
                            particleContext.rotate(by: Angle(radians: angle))

                            let rect = CGRect(
                                x: -particle.size.width / 2,
                                y: -particle.size.height / 2,
                                width: particle.size.width,
                                height: particle.size.height
                            )

                            switch particle.shape {
                            case .rectangle:
                                particleContext.fill(Path(rect), with: .color(particle.color))
                            case .circle:
                                particleContext.fill(Path(ellipseIn: rect), with: .color(particle.color))
                            case .ribbon:
                                let ribbon = CGRect(
                                    x: -particle.size.width / 2,
                                    y: -particle.size.height / 2,
                                    width: particle.size.width * 0.45,
                                    height: particle.size.height * 1.35
                                )
                                particleContext.fill(Path(ribbon), with: .color(particle.color))
                            }
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
            let burst = index < particleCount / 2
            return Particle(
                originX: CGFloat.random(in: burst ? -220...220 : -320...320),
                originY: CGFloat.random(in: burst ? -40...20 : -120...40),
                color: colors.randomElement() ?? .accentColor,
                size: CGSize(
                    width: CGFloat.random(in: 7...14),
                    height: CGFloat.random(in: 10...20)
                ),
                rotation: Double.random(in: 0...360),
                speed: CGFloat.random(in: burst ? 140...220 : 100...180),
                drift: CGFloat.random(in: 18...48),
                spin: Double.random(in: -320...320),
                delay: Double(index) * delayStep + (burst ? 0 : 0.18),
                shape: ShapeKind.allCases.randomElement() ?? .rectangle
            )
        }
    }
}
