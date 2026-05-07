import Foundation

public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case original
    case webP
    case png
    case jpg

    public var displayName: String {
        switch self {
        case .original:
            return "原格式"
        case .webP:
            return "WebP"
        case .png:
            return "PNG"
        case .jpg:
            return "JPG"
        }
    }
}

public enum CompressionMode: String, Codable, CaseIterable, Sendable {
    case quality
    case targetSize

    public var displayName: String {
        switch self {
        case .quality:
            return "压缩强度"
        case .targetSize:
            return "文件大小"
        }
    }
}

public enum SaveMode: String, Codable, CaseIterable, Sendable {
    case originalFolder
    case overwriteOriginal
    case customFolder

    public var displayName: String {
        switch self {
        case .originalFolder:
            return "原文件夹"
        case .overwriteOriginal:
            return "覆盖原文件"
        case .customFolder:
            return "自定义文件夹"
        }
    }
}

public enum SourceFormat: String, Codable, Sendable {
    case jpeg
    case png
    case gif
    case svg
    case webP
    case tiff
    case bmp
    case heic
    case other
}

public enum OutputCodec: String, Sendable {
    case jpeg
    case png
    case gif
    case svg
    case webP

    public var fileExtension: String {
        switch self {
        case .jpeg:
            return "jpg"
        case .png:
            return "png"
        case .gif:
            return "gif"
        case .svg:
            return "svg"
        case .webP:
            return "webp"
        }
    }
}

public struct CompressionSettings: Codable, Sendable {
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var keepAspectRatio: Bool
    public var compressionMode: CompressionMode
    public var qualityLevel: Double
    public var targetSizeKB: Int
    public var outputFormat: OutputFormat
    public var saveMode: SaveMode
    public var customDirectory: URL?
    public var outputSuffix: String

    public init(
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        keepAspectRatio: Bool = true,
        compressionMode: CompressionMode = .quality,
        qualityLevel: Double = 3,
        targetSizeKB: Int = 300,
        outputFormat: OutputFormat = .webP,
        saveMode: SaveMode = .overwriteOriginal,
        customDirectory: URL? = nil,
        outputSuffix: String = "-compressed"
    ) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.keepAspectRatio = keepAspectRatio
        self.compressionMode = compressionMode
        self.qualityLevel = qualityLevel
        self.targetSizeKB = targetSizeKB
        self.outputFormat = outputFormat
        self.saveMode = saveMode
        self.customDirectory = customDirectory
        self.outputSuffix = outputSuffix
    }
}

public struct CompressionRequest: Sendable {
    public var inputURL: URL
    public var originalURL: URL
    public var settings: CompressionSettings

    public init(inputURL: URL, originalURL: URL, settings: CompressionSettings) {
        self.inputURL = inputURL
        self.originalURL = originalURL
        self.settings = settings
    }
}

public struct ImageMetadata: Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let fileSize: Int64
    public let isAnimated: Bool
    public let sourceFormat: SourceFormat

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        fileSize: Int64,
        isAnimated: Bool,
        sourceFormat: SourceFormat
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.isAnimated = isAnimated
        self.sourceFormat = sourceFormat
    }
}

public struct CompressionResult: Sendable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let originalSize: Int64
    public let outputSize: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let codec: OutputCodec
    public let note: String?

    public var savedRatio: Double {
        guard originalSize > 0 else { return 0 }
        return 1 - (Double(outputSize) / Double(originalSize))
    }

    public init(
        sourceURL: URL,
        destinationURL: URL,
        originalSize: Int64,
        outputSize: Int64,
        pixelWidth: Int,
        pixelHeight: Int,
        codec: OutputCodec,
        note: String?
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.codec = codec
        self.note = note
    }
}

public enum CompressionError: LocalizedError, Sendable {
    case unsupportedInput(URL)
    case unreadableImage(URL)
    case rasterizationFailed(URL)
    case encodingFailed(OutputCodec)
    case writeFailed(URL)
    case customFolderMissing
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedInput(let url):
            return "暂不支持处理 \(url.lastPathComponent)"
        case .unreadableImage(let url):
            return "无法读取 \(url.lastPathComponent)"
        case .rasterizationFailed(let url):
            return "无法将 \(url.lastPathComponent) 渲染为位图"
        case .encodingFailed(let codec):
            return "导出 \(codec.fileExtension.uppercased()) 失败"
        case .writeFailed(let url):
            return "写入文件失败: \(url.path)"
        case .customFolderMissing:
            return "请选择自定义输出文件夹"
        case .commandFailed(let message):
            return message
        }
    }
}
