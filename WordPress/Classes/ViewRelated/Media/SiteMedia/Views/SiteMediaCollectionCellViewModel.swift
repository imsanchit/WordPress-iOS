import UIKit

final class SiteMediaCollectionCellViewModel {
    let mediaID: TaggedManagedObjectID<Media>

    var onImageLoaded: ((UIImage) -> Void)?

    @Published private(set) var overlayState: CircularProgressView.State?
    @Published private(set) var durationText: String?
    @Published private(set) var documentInfo: SiteMediaDocumentInfoViewModel?

    @Published var badge: BadgeType?

    private let media: Media
    private let mediaType: MediaType
    private let service: MediaImageService
    private let coordinator: MediaCoordinator
    private let cache: MemoryCache

    private var isVisible = false
    private var isPrefetchingNeeded = false
    private var imageTask: Task<Void, Never>?
    private var progressObserver: NSKeyValueObservation?
    private var observations: [NSKeyValueObservation] = []

    enum BadgeType {
        case unordered
        case ordered(index: Int)
    }

    deinit {
        imageTask?.cancel()
    }

    init(media: Media,
         service: MediaImageService = .shared,
         coordinator: MediaCoordinator = .shared,
         cache: MemoryCache = .shared) {
        self.mediaID = TaggedManagedObjectID(media)
        self.media = media
        self.mediaType = media.mediaType
        self.service = service
        self.coordinator = coordinator
        self.cache = cache

        observations.append(media.observe(\.remoteStatusNumber, options: [.initial, .new]) { [weak self] _, _ in
            self?.updateOverlayState()
        })

        observations.append(media.observe(\.localURL, options: [.new]) { [weak self] media, _ in
            self?.didUpdateLocalThumbnail()
        })

        switch mediaType {
        case .document, .powerpoint, .audio:
            observations.append(media.observe(\.filename, options: [.initial, .new]) { [weak self] media, _ in
                self?.documentInfo = SiteMediaDocumentInfoViewModel.make(with: media)
            })
        default: break
        }

        if mediaType == .video {
            observations.append(media.observe(\.length, options: [.initial, .new]) { [weak self] media, _ in
                // Using `rounded()` to match the behavior of the Photos app
                self?.durationText = makeString(forDuration: media.duration().rounded())
            })
        }
    }

    // MARK: - View Lifecycle

    func onAppear() {
        guard !isVisible else { return }
        isVisible = true
        fetchThumbnailIfNeeded()
    }

    func onDisappear() {
        guard isVisible else { return }
        isVisible = false
        cancelThumbnailRequestIfNeeded()
    }

    func startPrefetching() {
        guard !isPrefetchingNeeded else { return }
        isPrefetchingNeeded = true
        fetchThumbnailIfNeeded()
    }

    func cancelPrefetching() {
        guard isPrefetchingNeeded else { return }
        isPrefetchingNeeded = false
        cancelThumbnailRequestIfNeeded()
    }

    // MARK: - Loading Thumbnail

    private var supportsThumbnails: Bool {
        mediaType == .image || mediaType == .video
    }

    private func fetchThumbnailIfNeeded() {
        guard supportsThumbnails else {
            return
        }
        guard isVisible || isPrefetchingNeeded else {
            return
        }
        guard imageTask == nil else {
            return // Already loading
        }
        guard getCachedThubmnail() == nil else {
            return // Already cached  in memory
        }
        imageTask = Task { @MainActor [service, media, weak self] in
            do {
                let image = try await service.thumbnail(for: media)
                self?.didFinishLoading(with: image)
            } catch {
                self?.didFinishLoading(with: nil)
            }
        }
    }

    private func cancelThumbnailRequestIfNeeded() {
        guard !isVisible && !isPrefetchingNeeded else { return }
        imageTask?.cancel()
        imageTask = nil
    }

    private func didFinishLoading(with image: UIImage?) {
        if let image {
            cache.setImage(image, forKey: makeCacheKey(for: media))
        }
        if !Task.isCancelled {
            if let image {
                onImageLoaded?(image)
                documentInfo = nil
            } else {
                documentInfo = SiteMediaDocumentInfoViewModel.make(with: media)
            }
            imageTask = nil
        }
    }

    /// Returns the image from the memory cache.
    func getCachedThubmnail() -> UIImage? {
        guard supportsThumbnails else { return nil}
        return cache.getImage(forKey: makeCacheKey(for: media))
    }

    private func makeCacheKey(for media: Media) -> String {
        "thumbnail-\(media.objectID)"
    }

    // Monitors thumbnails generated by `MediaImportService`.
    private func didUpdateLocalThumbnail() {
        guard media.remoteStatus != .sync, media.localURL != nil else { return }
        fetchThumbnailIfNeeded()
    }

    // MARK: - Upload State

    private func updateOverlayState() {
        switch media.remoteStatus {
        case .pushing, .processing:
            if let progress = coordinator.progress(for: media) {
                progressObserver = progress.observe(\Progress.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                    self?.didUpdateProgress(progress)
                }
            } else {
                overlayState = .indeterminate
            }
        case .failed:
            overlayState = .retry
        case .sync:
            overlayState = nil
        default:
            break
        }
    }

    private func didUpdateProgress(_ progress: Progress) {
        guard media.remoteStatus == .processing || media.remoteStatus == .pushing else { return }

        // It takes a second or two (or more, depending on the file size) to
            // process the uploaded file after the progress stop reporting updates,
            // so the app switches to the indeterminate progress indicator.
        if progress.fractionCompleted > 0.99 {
            overlayState = .indeterminate
        } else {
            overlayState = .progress(progress.fractionCompleted * 0.9)
        }
    }

    // MARK: - Accessibility

    var accessibilityLabel: String? {
        let formattedDate = media.creationDate.map(accessibilityDateFormatter.string) ?? Strings.accessibilityUnknownCreationDate

        switch mediaType {
        case .image:
            return String(format: Strings.accessibilityLabelImage, formattedDate)
        case .video:
            return String(format: Strings.accessibilityLabelVideo, formattedDate)
        case .audio:
            return String(format: Strings.accessibilityLabelAudio, formattedDate)
        case .document, .powerpoint:
            return String(format: Strings.accessibilityLabelDocument, media.filename ?? formattedDate)
        @unknown default:
            return nil
        }
    }

    var accessibilityHint: String { Strings.accessibilityHint }
}

// MARK: - Helpers

private enum Strings {
    static let accessibilityUnknownCreationDate = NSLocalizedString("siteMedia.accessibilityUnknownCreationDate", value: "Unknown creation date", comment: "Accessibility label to use when creation date from media asset is not know.")
    static let accessibilityLabelImage = NSLocalizedString("siteMedia.accessibilityLabelImage", value: "Image, %@", comment: "Accessibility label for image thumbnails in the media collection view. The parameter is the creation date of the image.")
    static let accessibilityLabelVideo = NSLocalizedString("siteMedia.accessibilityLabelVideo", value: "Video, %@", comment: "Accessibility label for video thumbnails in the media collection view. The parameter is the creation date of the video.")
    static let accessibilityLabelAudio = NSLocalizedString("siteMedia.accessibilityLabelAudio", value: "Audio, %@", comment: "Accessibility label for audio items in the media collection view. The parameter is the creation date of the audio.")
    static let accessibilityLabelDocument = NSLocalizedString("siteMedia.accessibilityLabelDocument", value: "Document, %@", comment: "Accessibility label for other media items in the media collection view. The parameter is the filename file.")
    static let accessibilityHint = NSLocalizedString("siteMedia.cellAccessibilityHint", value: "Select media.", comment: "Accessibility hint for actions when displaying media items.")
}

private let accessibilityDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.doesRelativeDateFormatting = true
    formatter.dateStyle = .full
    formatter.timeStyle = .short
    return formatter
}()

// MARK: - Helpers (Duration Formatter)

private func makeString(forDuration duration: TimeInterval) -> String? {
    let hours = Int(duration / 3600)
    if hours > 0 {
        return longDurationFormatter.string(from: duration)
    } else {
        return shortDurationFormatter.string(from: duration)
    }
}

private let longDurationFormatter = makeFormatter(units: [.hour, .minute, .second])
private let shortDurationFormatter = makeFormatter(units: [.minute, .second])

private func makeFormatter(units: NSCalendar.Unit) -> DateComponentsFormatter {
    let formatter = DateComponentsFormatter()
    formatter.zeroFormattingBehavior = .pad
    formatter.allowedUnits = units
    return formatter
}
