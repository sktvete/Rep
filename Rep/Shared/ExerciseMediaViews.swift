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
    var loadsImages: Bool = true
    var listIndex: Int? = nil
    let onSelect: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShowDetails) {
                ExerciseMediaThumbnail(
                    exercise: exercise,
                    loadsImage: loadsImages,
                    listIndex: listIndex
                )
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
    var size: CGFloat = ExerciseThumbnailSizing.pickerPointSize
    var loadsImage: Bool = true
    var listIndex: Int? = nil

    private var mediaURL: URL? {
        ExerciseCatalogMedia.resolvedURL(for: exercise)
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.exerciseThumbnailScopeID) private var scopeID
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var didFail = false
    @State private var isOnScreen = false

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
        .onAppear {
            isOnScreen = true
            if let scopeID, let listIndex {
                ExerciseThumbnailListTracker.shared.registerVisibleRow(scopeID: scopeID, index: listIndex)
            }
            applyCachedImageIfAvailable()
        }
        .onDisappear {
            isOnScreen = false
        }
        .task(id: loadTaskID) {
            guard let mediaURL else {
                image = nil
                loadedURL = nil
                didFail = false
                return
            }
            let maxPixel = resolvedMaxPixel
            if let cached = ExerciseThumbnailSyncCache.image(url: mediaURL, maxPixel: maxPixel) {
                image = cached
                loadedURL = mediaURL
                didFail = false
                return
            }
            if loadedURL == mediaURL, image != nil {
                return
            }
            // Prefetched rows paint from sync cache above. Only hit the network when allowed.
            guard loadsImage else { return }
            didFail = false
            let loaded = await ExerciseThumbnailCache.shared.thumbnail(
                for: mediaURL,
                maxPixelSize: maxPixel,
                priority: loadPriority
            )
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
                loadedURL = mediaURL
            } else {
                didFail = true
            }
        }
    }

    private var resolvedMaxPixel: CGFloat {
        size == ExerciseThumbnailSizing.pickerPointSize
            ? ExerciseThumbnailSizing.pickerMaxPixel
            : min(64, size * min(displayScale, 2))
    }

    private func applyCachedImageIfAvailable() {
        guard let mediaURL else { return }
        guard let cached = ExerciseThumbnailSyncCache.image(
            url: mediaURL,
            maxPixel: resolvedMaxPixel
        ) else { return }
        image = cached
        loadedURL = mediaURL
        didFail = false
    }

    private var loadPriority: ExerciseThumbnailLoadPriority {
        guard let scopeID else {
            return isOnScreen ? .onScreen(listIndex: listIndex ?? 0) : .background
        }
        return ExerciseThumbnailScopeCenter.shared.priority(
            scopeID: scopeID,
            listIndex: listIndex,
            isOnScreen: isOnScreen
        )
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
/// Media can be animated GIFs or pinned catalog JPEGs. Rendering animated media directly
/// in hundreds of rows decodes every frame and thrashes memory while the list scrolls.
/// This cache downsamples only the first frame to the displayed size via ImageIO and keeps
/// results in memory, so scrolling rows remain static and smooth. On-disk byte caching is
/// handled by the shared `URLCache`.
///
/// Loads are prioritized: on-screen rows first, then a short prefetch window below the
/// fold, then everything else.
actor ExerciseThumbnailCache {
    static let shared = ExerciseThumbnailCache()

    private struct QueuedLoad {
        let key: String
        let url: URL
        let maxPixel: CGFloat
        var priority: ExerciseThumbnailLoadPriority
    }

    private let memory = NSCache<NSString, UIImage>()
    private var queue: [QueuedLoad] = []
    private var waiters: [String: [CheckedContinuation<UIImage?, Never>]] = [:]
    private var inFlight: Set<String> = []
    private var activeCount = 0
    /// Keep decode concurrency low — ImageIO on GIFs is the list hitch source.
    private let maxConcurrent = 2
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        memory.countLimit = 320
        memory.totalCostLimit = 32 * 1_024 * 1_024
    }

    func thumbnail(
        for url: URL,
        maxPixelSize: CGFloat,
        priority: ExerciseThumbnailLoadPriority = .background
    ) async -> UIImage? {
        let maxPixel = ExerciseThumbnailSizing.canonicalPixelSize(maxPixelSize)
        let key = ExerciseThumbnailSizing.cacheKey(url: url, maxPixel: maxPixel)

        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let synced = ExerciseThumbnailSyncCache.image(forKey: key) {
            memory.setObject(synced, forKey: key as NSString)
            return synced
        }
        if inFlight.contains(key) {
            return await wait(for: key, url: url, maxPixel: maxPixel, priority: priority)
        }

        return await wait(for: key, url: url, maxPixel: maxPixel, priority: priority)
    }

    private func wait(
        for key: String,
        url: URL,
        maxPixel: CGFloat,
        priority: ExerciseThumbnailLoadPriority
    ) async -> UIImage? {
        enqueue(key: key, url: url, maxPixel: maxPixel, priority: priority)
        return await withCheckedContinuation { continuation in
            waiters[key, default: []].append(continuation)
        }
    }

    private func enqueue(
        key: String,
        url: URL,
        maxPixel: CGFloat,
        priority: ExerciseThumbnailLoadPriority
    ) {
        if let index = queue.firstIndex(where: { $0.key == key }) {
            if priority < queue[index].priority {
                queue[index].priority = priority
                queue.sort { $0.priority < $1.priority }
            }
        } else {
            queue.append(QueuedLoad(key: key, url: url, maxPixel: maxPixel, priority: priority))
            queue.sort { $0.priority < $1.priority }
        }
        drain()
    }

    private func drain() {
        guard activeCount < maxConcurrent else { return }
        guard let next = queue.first else { return }
        queue.removeFirst()
        guard !inFlight.contains(next.key) else {
            drain()
            return
        }

        inFlight.insert(next.key)
        activeCount += 1

        let key = next.key
        let url = next.url
        let maxPixel = next.maxPixel
        let priority = next.priority

        Task.detached(priority: priority.taskPriority) { [session] in
            let image = await Self.fetchImage(
                url: url,
                maxPixel: maxPixel,
                session: session
            )
            await ExerciseThumbnailCache.shared.finish(
                key: key,
                image: image
            )
        }
    }

    private func finish(key: String, image: UIImage?) {
        inFlight.remove(key)
        activeCount = max(0, activeCount - 1)
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            memory.setObject(image, forKey: key as NSString, cost: cost)
            ExerciseThumbnailSyncCache.store(image, forKey: key)
        }
        let continuations = waiters.removeValue(forKey: key) ?? []
        for continuation in continuations {
            continuation.resume(returning: image)
        }
        drain()
    }

    func clearMemory() {
        memory.removeAllObjects()
        ExerciseThumbnailSyncCache.clear()
        queue.removeAll()
        inFlight.removeAll()
        activeCount = 0
        for continuations in waiters.values {
            for continuation in continuations {
                continuation.resume(returning: nil)
            }
        }
        waiters.removeAll()
    }

    private static func fetchImage(
        url: URL,
        maxPixel: CGFloat,
        session: URLSession
    ) async -> UIImage? {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let image = downsample(data: data, maxPixelSize: maxPixel)
        else { return nil }
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

    let exercise: Exercise

    private var mediaURL: URL? {
        ExerciseCatalogMedia.resolvedURL(for: exercise)
    }

    private var sourceURL: URL? {
        guard let value = exercise.sourceURLString,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    private var instructionSteps: [String] {
        ExerciseInstructionFormatter.steps(from: exercise.instructions)
    }

    private var userNotes: String? {
        guard let value = exercise.userNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private var helpVideoURL: URL? {
        guard let videoID = exercise.helpYouTubeVideoID,
              ExerciseHelpVideoCatalog.isValidYouTubeVideoID(videoID)
        else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    private var helpVideoChannel: String? {
        exercise.helpVideoChannel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    media

                    if let helpVideoURL {
                        helpVideoLink(helpVideoURL)
                    }

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

                    if let userNotes {
                        notes(userNotes)
                    }

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
            .navigationTitle("Exercise Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.tint)
                Text("Movement reference coming soon")
                    .font(.subheadline.weight(.medium))
                    .repSecondaryText()
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(.rect(cornerRadius: RepVisualSystem.cardRadius))
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
                            Text("\(index + 1)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor, in: Circle())
                                .accessibilityHidden(true)

                            Button {
                                ExerciseStepSpeechService.shared.speakStep(number: index + 1, text: step)
                            } label: {
                                Text(step)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Read step \(index + 1): \(step)")
                            .accessibilityHint("Reads this instruction aloud")
                        }
                        .padding(.vertical, 12)

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

    private func helpVideoLink(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch video breakdown")
                        .font(.subheadline.weight(.semibold))
                    if let helpVideoChannel {
                        Text(helpVideoChannel)
                            .font(.caption)
                            .repSecondaryText()
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
            .padding()
            .repSurface(cornerRadius: RepVisualSystem.controlRadius)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch video breakdown on YouTube")
        .accessibilityHint("Opens the reviewed technique video externally")
    }

    private func notes(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.title3.bold())
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .repSurface(cornerRadius: RepVisualSystem.cardRadius)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
