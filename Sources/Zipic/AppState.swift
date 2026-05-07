import AppKit
import Combine
import Foundation
import SwiftUI
import TuyaCore
import UniformTypeIdentifiers

@MainActor
final class CompressionItem: ObservableObject, Identifiable {
    enum State {
        case pending
        case processing
        case completed
        case failed(String)

        var text: String {
            switch self {
            case .pending:
                return "等待处理"
            case .processing:
                return "正在压缩"
            case .completed:
                return "已完成"
            case .failed:
                return "处理失败"
            }
        }

        var tint: Color {
            switch self {
            case .pending:
                return .secondary
            case .processing:
                return .accentColor
            case .completed:
                return .green
            case .failed:
                return .red
            }
        }
    }

    let id = UUID()
    let sourceURL: URL
    var backupURL: URL?

    @Published var preview: NSImage?
    @Published var dimensionsText = "--"
    @Published var originalSizeText = "--"
    @Published var outputSizeText = "--"
    @Published var savedText = "--"
    @Published var destinationText = "尚未输出"
    @Published var noteText: String?
    @Published var state: State = .pending
    @Published var outputURL: URL?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var settings: CompressionSettings {
        didSet { persistSettings() }
    }
    @Published var jobs: [CompressionItem] = []
    @Published var showExtendedSettings = true
    @Published var isCompressing = false
    @Published var alertMessage: String?

    private let settingsKey = "Zipic.Settings"
    private let byteFormatter: ByteCountFormatter
    private let backupDirectory: URL
    private var compressionRunID = UUID()

    init() {
        self.byteFormatter = ByteCountFormatter()
        self.byteFormatter.countStyle = .file
        self.byteFormatter.allowedUnits = [.useKB, .useMB]

        let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ZipicSession-\(UUID().uuidString)", isDirectory: true)
        self.backupDirectory = workingDirectory
        try? FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(CompressionSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = CompressionSettings()
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: backupDirectory)
    }

    var summaryText: String {
        if jobs.isEmpty {
            return "支持 JPG / PNG / GIF / SVG / WebP"
        }
        if isCompressing {
            return "正在逐张压缩并及时释放内存"
        }
        return "共 \(jobs.count) 张图片"
    }

    func importFiles(with urls: [URL]) {
        let supported = urls.filter { Self.isSupportedFile($0) }
        guard !supported.isEmpty else { return }

        var newItems: [CompressionItem] = []
        for url in supported {
            if jobs.contains(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
                continue
            }

            let item = CompressionItem(sourceURL: url)
            jobs.append(item)
            newItems.append(item)
            Task { await loadPreviewAndMetadata(for: item) }
        }

        guard !newItems.isEmpty else { return }
        compress(items: newItems)
    }

    func clearJobs() {
        compressionRunID = UUID()
        jobs.removeAll()
        isCompressing = false
    }

    func recompressAll() {
        guard !jobs.isEmpty else { return }
        compress(items: jobs)
    }

    func openImporter() {
        let panel = NSOpenPanel()
        panel.title = "添加图片"
        panel.allowedContentTypes = Self.supportedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            importFiles(with: panel.urls)
        }
    }

    func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            settings.customDirectory = panel.url
        }
    }

    func revealOutput(of item: CompressionItem) {
        guard let outputURL = item.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    func optionalIntBinding(_ keyPath: WritableKeyPath<CompressionSettings, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard let value = self.settings[keyPath: keyPath] else { return "" }
                return String(value)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.settings[keyPath: keyPath] = Int(trimmed)
            }
        )
    }

    func intBinding(_ keyPath: WritableKeyPath<CompressionSettings, Int>) -> Binding<String> {
        Binding(
            get: { String(self.settings[keyPath: keyPath]) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.settings[keyPath: keyPath] = max(1, Int(trimmed) ?? self.settings[keyPath: keyPath])
            }
        )
    }

    private func compress(items: [CompressionItem]) {
        let runID = UUID()
        compressionRunID = runID
        isCompressing = true

        for item in items {
            item.state = .pending
            item.outputURL = nil
            item.destinationText = "尚未输出"
            item.outputSizeText = "--"
            item.savedText = "--"
            item.noteText = nil
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            for item in items {
                let shouldContinue = await MainActor.run { self.compressionRunID == runID }
                guard shouldContinue else { return }

                await MainActor.run {
                    item.state = .processing
                }

                do {
                    let inputURL = try await self.prepareInputURL(for: item)
                    let request = CompressionRequest(
                        inputURL: inputURL,
                        originalURL: item.sourceURL,
                        settings: await MainActor.run { self.settings }
                    )
                    let result = try await CompressionEngine.compress(request)

                    let stillValid = await MainActor.run { self.compressionRunID == runID }
                    guard stillValid else { return }

                    await MainActor.run {
                        item.outputURL = result.destinationURL
                        item.destinationText = result.destinationURL.path
                        item.outputSizeText = self.byteFormatter.string(fromByteCount: result.outputSize)
                        item.savedText = String(format: "节省 %.0f%%", max(0, result.savedRatio * 100))
                        item.noteText = result.note
                        item.dimensionsText = "\(result.pixelWidth) × \(result.pixelHeight)"
                        item.state = .completed
                    }
                } catch {
                    let stillValid = await MainActor.run { self.compressionRunID == runID }
                    guard stillValid else { return }

                    await MainActor.run {
                        item.state = .failed(error.localizedDescription)
                        item.noteText = error.localizedDescription
                        self.alertMessage = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                if self.compressionRunID == runID {
                    self.isCompressing = false
                }
            }
        }
    }

    private func prepareInputURL(for item: CompressionItem) async throws -> URL {
        if settings.saveMode != .overwriteOriginal {
            return item.sourceURL
        }

        if let backupURL = item.backupURL, FileManager.default.fileExists(atPath: backupURL.path) {
            return backupURL
        }

        let backupURL = backupDirectory.appendingPathComponent("\(item.id.uuidString)-\(item.sourceURL.lastPathComponent)")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.copyItem(at: item.sourceURL, to: backupURL)
        }
        item.backupURL = backupURL
        return backupURL
    }

    private func loadPreviewAndMetadata(for item: CompressionItem) async {
        async let preview = CompressionEngine.loadPreview(at: item.sourceURL)
        async let metadata = CompressionEngine.inspectImage(at: item.sourceURL)

        let loadedPreview = await preview
        let loadedMetadata = try? await metadata

        await MainActor.run {
            item.preview = loadedPreview
            if let loadedMetadata {
                item.dimensionsText = "\(loadedMetadata.pixelWidth) × \(loadedMetadata.pixelHeight)"
                item.originalSizeText = self.byteFormatter.string(fromByteCount: loadedMetadata.fileSize)
            }
        }
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    static let supportedExtensions = ["jpg", "jpeg", "png", "gif", "svg", "webp", "heic", "heif", "tiff", "tif", "bmp"]
    static let supportedContentTypes: [UTType] = supportedExtensions.compactMap { UTType(filenameExtension: $0) }

    static func isSupportedFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
