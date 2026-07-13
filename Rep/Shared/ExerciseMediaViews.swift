import ImageIO
import SwiftUI
import UIKit
import WebKit

struct ExerciseCatalogStatusView: View {
    let isLoading: Bool
    let progress: Double?
    let errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        if isLoading {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating exercise catalog…")
                        .font(.caption.weight(.medium))
                    Spacer()
                    if let progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .repSecondaryText()
                    }
                }
                if let progress {
                    ProgressView(value: progress)
                        .tint(.accentColor)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Updating exercise catalog")
            .accessibilityValue(progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "In progress")
        } else if let errorMessage {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Catalog update paused")
                        .font(.caption.weight(.semibold))
                    Text(errorMessage)
                        .font(.caption2)
                        .repSecondaryText()
                        .lineLimit(2)
                }
                Spacer()
                Button("Retry", action: onRetry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

struct ExercisePickerRow: View {
    let exercise: Exercise
    let loadsImages: Bool
    let onSelect: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShowDetails) {
                ExerciseMediaThumbnail(exercise: exercise, loadsImage: loadsImages)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show how to perform \(exercise.name)")

            Button(action: onSelect) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text("\(exercise.primaryMuscleGroup.displayName) · \(exercise.equipment.displayName)")
                            .font(.caption)
                            .repSecondaryText()
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(exercise.name)")
            .accessibilityHint("Adds this exercise to your workout or routine")
        }
    }
}

struct ExerciseMediaThumbnail: View {
    let exercise: Exercise
    var size: CGFloat = 58
    var loadsImage: Bool = true

    private var mediaURL: URL? {
        guard let value = exercise.mediaURLString,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail || mediaURL == nil {
                placeholder
            } else {
                placeholder
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .frame(width: size, height: size)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: max(10, size * 0.2)))
        .overlay {
            RoundedRectangle(cornerRadius: max(10, size * 0.2))
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .accessibilityHidden(true)
        .task(id: loadTaskID) {
            image = nil
            didFail = false
            guard loadsImage, let mediaURL else { return }
            let maxPixel = size * max(1, displayScale)
            let loaded = await ExerciseThumbnailCache.shared.thumbnail(for: mediaURL, maxPixelSize: maxPixel)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
            } else {
                didFail = true
            }
        }
    }

    private var loadTaskID: String {
        guard loadsImage, let mediaURL else { return "idle" }
        return mediaURL.absoluteString
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbolName)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.tint)
        }
    }

    private var symbolName: String {
        switch exercise.primaryMuscleGroup {
        case .chest, .back, .shoulders, .biceps, .triceps:
            "figure.strengthtraining.traditional"
        case .quadriceps, .hamstrings, .glutes, .calves:
            "figure.strengthtraining.functional"
        case .core:
            "figure.core.training"
        case .fullBody, .other:
            "dumbbell.fill"
        }
    }
}

/// Loads and caches small, static exercise thumbnails.
///
/// Catalog media are animated GIFs. Rendering hundreds of them with `AsyncImage` decodes
/// every frame and thrashes memory while the list scrolls. This cache downsamples just
/// the first frame to the displayed size via ImageIO and keeps results in memory, so the
/// picker stays smooth even with the full catalog. On-disk byte caching is handled by the
/// shared `URLCache`.
actor ExerciseThumbnailCache {
    static let shared = ExerciseThumbnailCache()

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        memory.countLimit = 400
    }

    func thumbnail(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let maxPixel = max(1, maxPixelSize)
        let key = "\(url.absoluteString)|\(Int(maxPixel))"

        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<UIImage?, Never>.detached(priority: .utility) { [session] in
            var request = URLRequest(url: url)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = Self.downsample(data: data, maxPixelSize: maxPixel)
            else { return nil }
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct ExerciseAnimatedMediaView: UIViewRepresentable {
    let url: URL
    let accessibilityLabel: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isAccessibilityElement = true
        webView.accessibilityLabel = accessibilityLabel
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url

        let source = htmlEscaped(url.absoluteString)
        let isVideo = ["mp4", "mov", "m4v", "webm"].contains(url.pathExtension.lowercased())
        let media = isVideo
            ? "<video src=\"\(source)\" controls playsinline preload=\"metadata\"></video>"
            : "<img src=\"\(source)\" alt=\"Exercise demonstration\">"
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <style>
            * { box-sizing: border-box; }
            html, body { width: 100%; height: 100%; margin: 0; background: transparent; overflow: hidden; }
            body { display: flex; align-items: center; justify-content: center; }
            img, video { display: block; width: 100%; height: 100%; object-fit: contain; }
          </style>
        </head>
        <body>\(media)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let exercise: Exercise

    @State private var catalogService = ExerciseDBCatalogService()
    @State private var isLoadingReference = false
    @State private var referenceError: String?

    private var mediaURL: URL? {
        guard let value = exercise.mediaURLString,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    private var sourceURL: URL? {
        guard let value = exercise.sourceURLString,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    private var instructionSteps: [String] {
        ExerciseInstructionFormatter.steps(from: exercise.instructions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    media

                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.name)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) {
                                Label(muscleSummary, systemImage: "figure.strengthtraining.traditional")
                                Label(exercise.equipment.displayName, systemImage: "dumbbell")
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Label(muscleSummary, systemImage: "figure.strengthtraining.traditional")
                                Label(exercise.equipment.displayName, systemImage: "dumbbell")
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .repSecondaryText()
                    }

                    instructions

                    if let sourceURL {
                        Link(destination: sourceURL) {
                            HStack(spacing: 10) {
                                Image(systemName: "safari")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Exercise source")
                                        .font(.caption)
                                        .repSecondaryText()
                                    Text(exercise.sourceName ?? "View original")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding()
                            .repSurface(cornerRadius: RepVisualSystem.controlRadius)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in your browser")
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            .background(RepScreenBackground())
            .navigationTitle("Form Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: exercise.mediaURLString) {
                await loadReferenceIfNeeded()
            }
        }
    }

    private var muscleSummary: String {
        let muscles = [exercise.primaryMuscleGroup] + exercise.secondaryMuscleGroups
        return muscles
            .reduce(into: [MuscleGroup]()) { result, muscle in
                if !result.contains(muscle) { result.append(muscle) }
            }
            .map(\.displayName)
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var media: some View {
        if let mediaURL {
            ExerciseAnimatedMediaView(
                url: mediaURL,
                accessibilityLabel: "Animated demonstration of \(exercise.name)"
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: RepVisualSystem.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RepVisualSystem.cardRadius)
                    .strokeBorder(Color.primary.opacity(0.07))
            }
        } else {
            VStack(spacing: 10) {
                if isLoadingReference {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading movement reference…")
                        .font(.subheadline.weight(.medium))
                        .repSecondaryText()
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.tint)
                    Text(referenceError ?? "Movement reference coming soon")
                        .font(.subheadline.weight(.medium))
                        .repSecondaryText()
                        .multilineTextAlignment(.center)
                    if referenceError != nil {
                        Button("Try Again") {
                            Task { await loadReferenceIfNeeded() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(.rect(cornerRadius: RepVisualSystem.cardRadius))
        }
    }

    private func loadReferenceIfNeeded() async {
        guard mediaURL == nil, !isLoadingReference else { return }
        isLoadingReference = true
        referenceError = nil
        defer { isLoadingReference = false }

        do {
            let loaded = try await catalogService.enrichExerciseIfNeeded(exercise, in: modelContext)
            if !loaded, mediaURL == nil {
                referenceError = "No movement reference is available yet."
            }
        } catch is CancellationError {
            return
        } catch {
            referenceError = "Couldn’t load the movement reference."
        }
    }

    @ViewBuilder
    private var instructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How to perform")
                    .font(.title3.bold())

                if !instructionSteps.isEmpty {
                    Text("\(instructionSteps.count) steps")
                        .font(.subheadline)
                        .repSecondaryText()
                }
            }

            if instructionSteps.isEmpty {
                Text("Form guidance is not available for this exercise yet.")
                    .font(.subheadline)
                    .repSecondaryText()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(instructionSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Button {
                                ExerciseStepSpeechService.shared.speakStep(number: index + 1, text: step)
                            } label: {
                                Text("\(index + 1)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.accentColor, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Speak step \(index + 1)")

                            Text(step)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Step \(index + 1), \(step)")

                        if index < instructionSteps.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }

            Text("Use this as a general form guide. Adjust setup and technique for your body, equipment, and goals.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .repSurface(cornerRadius: RepVisualSystem.cardRadius)
    }
}
