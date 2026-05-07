import AppKit
import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing

public enum CompressionEngine {
    public static func inspectImage(at url: URL) async throws -> ImageMetadata {
        let fileSize = try fileSize(of: url)
        let format = sourceFormat(for: url, typeHint: nil)

        if format == .svg {
            let text = try String(contentsOf: url, encoding: .utf8)
            let size = svgCanvasSize(from: text) ?? CGSize(width: 2048, height: 2048)
            return ImageMetadata(
                pixelWidth: max(1, Int(size.width.rounded())),
                pixelHeight: max(1, Int(size.height.rounded())),
                fileSize: fileSize,
                isAnimated: false,
                sourceFormat: .svg
            )
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw CompressionError.unreadableImage(url)
        }

        let typeHint = CGImageSourceGetType(source)
        let detectedFormat = sourceFormat(for: url, typeHint: typeHint)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let frameCount = CGImageSourceGetCount(source)

        return ImageMetadata(
            pixelWidth: max(width, 1),
            pixelHeight: max(height, 1),
            fileSize: fileSize,
            isAnimated: detectedFormat == .gif && frameCount > 1,
            sourceFormat: detectedFormat
        )
    }

    public static func loadPreview(at url: URL, maxPixelSize: Int = 320) async -> NSImage? {
        let format = sourceFormat(for: url, typeHint: nil)

        if format == .svg {
            return await quickLookPreview(for: url, size: CGSize(width: maxPixelSize, height: maxPixelSize))
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    public static func compress(_ request: CompressionRequest) async throws -> CompressionResult {
        let metadata = try await inspectImage(at: request.inputURL)
        let codec = resolveOutputCodec(requested: request.settings.outputFormat, source: metadata.sourceFormat)
        let destination = try destinationURL(for: request.originalURL, settings: request.settings, codec: codec)
        var notes: [String] = []

        if request.settings.saveMode == .overwriteOriginal && request.originalURL.pathExtension.lowercased() != codec.fileExtension {
            notes.append("目标格式变化时，已安全输出为新文件")
        }

        switch (metadata.sourceFormat, codec) {
        case (.svg, .svg):
            let result = try compressSVG(
                request: request,
                metadata: metadata,
                destinationURL: destination,
                notes: notes
            )
            return result
        case (.gif, .gif) where metadata.isAnimated:
            return try compressAnimatedGIF(
                request: request,
                metadata: metadata,
                destinationURL: destination,
                notes: notes
            )
        default:
            return try await compressRasterAsset(
                request: request,
                metadata: metadata,
                codec: codec,
                destinationURL: destination,
                notes: notes
            )
        }
    }
}

private extension CompressionEngine {
    static func compressSVG(
        request: CompressionRequest,
        metadata: ImageMetadata,
        destinationURL: URL,
        notes: [String]
    ) throws -> CompressionResult {
        var svgText = try String(contentsOf: request.inputURL, encoding: .utf8)
        svgText = optimizeSVGText(svgText, metadata: metadata, settings: request.settings)
        let outputData = Data(svgText.utf8)

        try write(outputData, to: destinationURL)

        var mergedNotes = notes
        mergedNotes.append("SVG 已做文本精简")

        let targetSize = resolvedSize(
            from: CGSize(width: metadata.pixelWidth, height: metadata.pixelHeight),
            settings: request.settings
        )

        return CompressionResult(
            sourceURL: request.originalURL,
            destinationURL: destinationURL,
            originalSize: metadata.fileSize,
            outputSize: Int64(outputData.count),
            pixelWidth: targetSize.width.pixelValue,
            pixelHeight: targetSize.height.pixelValue,
            codec: .svg,
            note: mergedNotes.joined(separator: " · ")
        )
    }

    static func compressAnimatedGIF(
        request: CompressionRequest,
        metadata: ImageMetadata,
        destinationURL: URL,
        notes: [String]
    ) throws -> CompressionResult {
        guard let source = CGImageSourceCreateWithURL(request.inputURL as CFURL, nil) else {
            throw CompressionError.unreadableImage(request.inputURL)
        }

        let frameCount = CGImageSourceGetCount(source)
        let originalSize = CGSize(width: metadata.pixelWidth, height: metadata.pixelHeight)
        let baseTarget = resolvedSize(from: originalSize, settings: request.settings)
        let targetBytes = request.settings.compressionMode == .targetSize ? Int64(request.settings.targetSizeKB) * 1024 : nil
        var scaleFactor = 1.0
        var bestData: Data?
        var bestSize = baseTarget

        repeat {
            let scaledSize = CGSize(
                width: max(1, floor(baseTarget.width * scaleFactor)),
                height: max(1, floor(baseTarget.height * scaleFactor))
            )

            let frameData = try autoreleasepool {
                let mutableData = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    mutableData,
                    outputUTI(for: .gif),
                    frameCount,
                    nil
                ) else {
                    throw CompressionError.encodingFailed(.gif)
                }

                if let globalProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
                   let gifProperties = globalProperties[kCGImagePropertyGIFDictionary] {
                    CGImageDestinationSetProperties(destination, [
                        kCGImagePropertyGIFDictionary: gifProperties
                    ] as CFDictionary)
                }

                for index in 0..<frameCount {
                    guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                        continue
                    }

                    let rendered = render(cgImage: frame, targetSize: scaledSize, flattenAlpha: false)
                    let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                    CGImageDestinationAddImage(destination, rendered, frameProperties)
                }

                guard CGImageDestinationFinalize(destination) else {
                    throw CompressionError.encodingFailed(.gif)
                }

                return mutableData as Data
            }

            bestData = frameData
            bestSize = scaledSize

            if let targetBytes, Int64(frameData.count) > targetBytes {
                scaleFactor *= 0.88
            } else {
                break
            }
        } while scaleFactor >= 0.22

        guard let outputData = bestData else {
            throw CompressionError.encodingFailed(.gif)
        }

        try write(outputData, to: destinationURL)

        var mergedNotes = notes
        mergedNotes.append("动画 GIF 通过逐帧缩放输出")

        return CompressionResult(
            sourceURL: request.originalURL,
            destinationURL: destinationURL,
            originalSize: metadata.fileSize,
            outputSize: Int64(outputData.count),
            pixelWidth: bestSize.width.pixelValue,
            pixelHeight: bestSize.height.pixelValue,
            codec: .gif,
            note: mergedNotes.joined(separator: " · ")
        )
    }

    static func compressRasterAsset(
        request: CompressionRequest,
        metadata: ImageMetadata,
        codec: OutputCodec,
        destinationURL: URL,
        notes: [String]
    ) async throws -> CompressionResult {
        let originalSize = CGSize(width: metadata.pixelWidth, height: metadata.pixelHeight)
        let baseTarget = resolvedSize(from: originalSize, settings: request.settings)
        let targetBytes = request.settings.compressionMode == .targetSize ? Int64(request.settings.targetSizeKB) * 1024 : nil

        var scaleFactor = 1.0
        var bestData: Data?
        var bestPixelSize = baseTarget
        var mergedNotes = notes

        repeat {
            let currentSize = CGSize(
                width: max(1, floor(baseTarget.width * scaleFactor)),
                height: max(1, floor(baseTarget.height * scaleFactor))
            )

            let raster = try await loadRasterImage(
                from: request.inputURL,
                metadata: metadata,
                targetSize: currentSize
            )

            let rendered = render(
                cgImage: raster,
                targetSize: currentSize,
                flattenAlpha: codec == .jpeg
            )

            let data = try encodeImage(
                rendered,
                codec: codec,
                settings: request.settings,
                targetBytes: targetBytes
            )

            bestData = data
            bestPixelSize = currentSize

            if codec == .jpeg && rendered.alphaInfo.containsAlpha {
                mergedNotes.append("JPG 输出已自动铺白透明背景")
            }

            if let targetBytes, Int64(data.count) > targetBytes {
                scaleFactor *= 0.9
            } else {
                break
            }
        } while scaleFactor >= 0.2

        guard let outputData = bestData else {
            throw CompressionError.encodingFailed(codec)
        }

        try write(outputData, to: destinationURL)

        if codec == .jpeg {
            try? optimizeJPEGInPlace(at: destinationURL)
        }

        let outputSize = try fileSize(of: destinationURL)
        let note = mergedNotes.isEmpty ? nil : Array(Set(mergedNotes)).joined(separator: " · ")

        return CompressionResult(
            sourceURL: request.originalURL,
            destinationURL: destinationURL,
            originalSize: metadata.fileSize,
            outputSize: outputSize,
            pixelWidth: bestPixelSize.width.pixelValue,
            pixelHeight: bestPixelSize.height.pixelValue,
            codec: codec,
            note: note
        )
    }

    static func loadRasterImage(
        from url: URL,
        metadata: ImageMetadata,
        targetSize: CGSize
    ) async throws -> CGImage {
        if metadata.sourceFormat == .svg {
            guard let preview = await quickLookPreview(for: url, size: targetSize),
                  let cgImage = preview.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CompressionError.rasterizationFailed(url)
            }
            return cgImage
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw CompressionError.unreadableImage(url)
        }

        let shouldDownsample = Int(targetSize.width) < metadata.pixelWidth || Int(targetSize.height) < metadata.pixelHeight

        if shouldDownsample {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(max(targetSize.width, targetSize.height)),
                kCGImageSourceShouldCacheImmediately: true
            ]

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
                return cgImage
            }
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            throw CompressionError.unreadableImage(url)
        }

        return cgImage
    }

    static func encodeImage(
        _ cgImage: CGImage,
        codec: OutputCodec,
        settings: CompressionSettings,
        targetBytes: Int64?
    ) throws -> Data {
        switch codec {
        case .jpeg:
            return try encodeJPEG(cgImage, settings: settings, targetBytes: targetBytes)
        case .png:
            return try encodeCGImage(cgImage, uti: outputUTI(for: .png), properties: [:])
        case .gif:
            return try encodeCGImage(cgImage, uti: outputUTI(for: .gif), properties: [:])
        case .svg:
            throw CompressionError.encodingFailed(.svg)
        case .webP:
            return try encodeWebP(cgImage, settings: settings, targetBytes: targetBytes)
        }
    }

    static func encodeJPEG(
        _ cgImage: CGImage,
        settings: CompressionSettings,
        targetBytes: Int64?
    ) throws -> Data {
        if let targetBytes {
            var low = 0.08
            var high = 0.96
            var bestUnder: Data?
            var smallestOver: Data?

            for _ in 0..<9 {
                let quality = (low + high) / 2
                let data = try encodeCGImage(
                    cgImage,
                    uti: outputUTI(for: .jpeg),
                    properties: [
                        kCGImageDestinationLossyCompressionQuality: quality
                    ]
                )

                if Int64(data.count) <= targetBytes {
                    bestUnder = data
                    low = quality
                } else {
                    smallestOver = smallerData(candidate: data, current: smallestOver)
                    high = quality
                }
            }

            if let bestUnder {
                return bestUnder
            }
            if let smallestOver {
                return smallestOver
            }
        }

        let quality = qualityFromLevel(settings.qualityLevel)
        return try encodeCGImage(
            cgImage,
            uti: outputUTI(for: .jpeg),
            properties: [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
        )
    }

    static func encodeWebP(
        _ cgImage: CGImage,
        settings: CompressionSettings,
        targetBytes: Int64?
    ) throws -> Data {
        if let cwebp = tool(named: "cwebp") {
            let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Zipic-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: workingDirectory) }

            let inputURL = workingDirectory.appendingPathComponent("input.png")
            let outputURL = workingDirectory.appendingPathComponent("output.webp")
            let pngData = try encodeCGImage(cgImage, uti: outputUTI(for: .png), properties: [:])
            try pngData.write(to: inputURL, options: .atomic)

            var arguments = ["-quiet", "-mt", "-metadata", "none"]
            if let targetBytes {
                arguments += ["-size", "\(targetBytes)", "-pass", "6"]
            } else {
                let quality = Int((qualityFromLevel(settings.qualityLevel) * 100).rounded())
                arguments += ["-q", "\(quality)"]
            }
            arguments += [inputURL.path, "-o", outputURL.path]

            try runProcess(executable: cwebp, arguments: arguments)
            return try Data(contentsOf: outputURL)
        }

        let properties: [CFString: Any]
        if let targetBytes {
            let quality = max(0.1, min(0.95, Double(targetBytes) / 500_000.0))
            properties = [kCGImageDestinationLossyCompressionQuality: quality]
        } else {
            properties = [kCGImageDestinationLossyCompressionQuality: qualityFromLevel(settings.qualityLevel)]
        }
        return try encodeCGImage(cgImage, uti: outputUTI(for: .webP), properties: properties)
    }

    static func encodeCGImage(
        _ cgImage: CGImage,
        uti: CFString,
        properties: [CFString: Any]
    ) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, uti, 1, nil) else {
            throw CompressionError.commandFailed("无法创建导出目标")
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CompressionError.commandFailed("图片导出未完成")
        }
        return output as Data
    }

    static func render(cgImage: CGImage, targetSize: CGSize, flattenAlpha: Bool) -> CGImage {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = flattenAlpha ? CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue) : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!

        if flattenAlpha {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? cgImage
    }

    static func resolvedSize(from original: CGSize, settings: CompressionSettings) -> CGSize {
        let maxWidth = settings.maxWidth.flatMap { $0 > 0 ? CGFloat($0) : nil }
        let maxHeight = settings.maxHeight.flatMap { $0 > 0 ? CGFloat($0) : nil }

        guard maxWidth != nil || maxHeight != nil else {
            return original
        }

        if settings.keepAspectRatio {
            let widthScale = maxWidth.map { $0 / original.width } ?? .greatestFiniteMagnitude
            let heightScale = maxHeight.map { $0 / original.height } ?? .greatestFiniteMagnitude
            let scale = min(widthScale, heightScale, 1.0)
            return CGSize(
                width: max(1, floor(original.width * scale)),
                height: max(1, floor(original.height * scale))
            )
        }

        return CGSize(
            width: max(1, min(maxWidth ?? original.width, original.width)),
            height: max(1, min(maxHeight ?? original.height, original.height))
        )
    }

    static func resolveOutputCodec(requested: OutputFormat, source: SourceFormat) -> OutputCodec {
        switch requested {
        case .jpg:
            return .jpeg
        case .png:
            return .png
        case .webP:
            return .webP
        case .original:
            switch source {
            case .jpeg, .heic:
                return .jpeg
            case .png:
                return .png
            case .gif:
                return .gif
            case .svg:
                return .svg
            case .webP:
                return .webP
            case .bmp, .other, .tiff:
                return .png
            }
        }
    }

    static func outputUTI(for codec: OutputCodec) -> CFString {
        switch codec {
        case .jpeg:
            return "public.jpeg" as CFString
        case .png:
            return "public.png" as CFString
        case .gif:
            return "com.compuserve.gif" as CFString
        case .svg:
            return "public.svg-image" as CFString
        case .webP:
            return "org.webmproject.webp" as CFString
        }
    }

    static func sourceFormat(for url: URL, typeHint: CFString?) -> SourceFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return .jpeg
        case "png":
            return .png
        case "gif":
            return .gif
        case "svg":
            return .svg
        case "webp":
            return .webP
        case "tif", "tiff":
            return .tiff
        case "bmp":
            return .bmp
        case "heic", "heif":
            return .heic
        default:
            break
        }

        guard let typeHint else { return .other }
        let identifier = typeHint as String
        if identifier.contains("jpeg") { return .jpeg }
        if identifier.contains("png") { return .png }
        if identifier.contains("gif") { return .gif }
        if identifier.contains("svg") { return .svg }
        if identifier.contains("webp") { return .webP }
        if identifier.contains("heic") || identifier.contains("heif") { return .heic }
        return .other
    }

    static func destinationURL(
        for originalURL: URL,
        settings: CompressionSettings,
        codec: OutputCodec
    ) throws -> URL {
        let fileManager = FileManager.default
        let sourceDirectory = originalURL.deletingLastPathComponent()
        let outputDirectory: URL

        switch settings.saveMode {
        case .originalFolder, .overwriteOriginal:
            outputDirectory = sourceDirectory
        case .customFolder:
            guard let customDirectory = settings.customDirectory else {
                throw CompressionError.customFolderMissing
            }
            outputDirectory = customDirectory
        }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let sourceExtension = originalURL.pathExtension.lowercased()
        let sameExtension = sourceExtension == codec.fileExtension

        if settings.saveMode == .overwriteOriginal, sameExtension, outputDirectory == sourceDirectory {
            return originalURL
        }

        let suffix = settings.outputSuffix
        let preferredName: String
        if settings.saveMode == .overwriteOriginal {
            preferredName = "\(baseName).\(codec.fileExtension)"
        } else {
            preferredName = "\(baseName)\(suffix).\(codec.fileExtension)"
        }

        var candidate = outputDirectory.appendingPathComponent(preferredName)
        if settings.saveMode != .overwriteOriginal {
            var index = 2
            while fileManager.fileExists(atPath: candidate.path) {
                let nextName = "\(baseName)\(suffix)-\(index).\(codec.fileExtension)"
                candidate = outputDirectory.appendingPathComponent(nextName)
                index += 1
            }
        }

        return candidate
    }

    static func quickLookPreview(for url: URL, size: CGSize) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: 2,
                representationTypes: .thumbnail
            )

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    static func optimizeSVGText(
        _ source: String,
        metadata: ImageMetadata,
        settings: CompressionSettings
    ) -> String {
        var output = source
        output = output.replacingOccurrences(of: "<!--([\\s\\S]*?)-->", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
        output = output.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)

        let targetSize = resolvedSize(from: CGSize(width: metadata.pixelWidth, height: metadata.pixelHeight), settings: settings)
        if settings.maxWidth != nil || settings.maxHeight != nil {
            output = replaceSVGAttribute(named: "width", value: "\(targetSize.width.pixelValue)", in: output)
            output = replaceSVGAttribute(named: "height", value: "\(targetSize.height.pixelValue)", in: output)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func replaceSVGAttribute(named attribute: String, value: String, in text: String) -> String {
        let pattern = "\(attribute)\\s*=\\s*\"[^\"]*\""
        if text.range(of: pattern, options: .regularExpression) != nil {
            return text.replacingOccurrences(of: pattern, with: "\(attribute)=\"\(value)\"", options: .regularExpression)
        }

        return text.replacingOccurrences(of: "<svg", with: "<svg \(attribute)=\"\(value)\"", options: [], range: text.range(of: "<svg"))
    }

    static func svgCanvasSize(from text: String) -> CGSize? {
        if let width = matchNumber(in: text, pattern: "width\\s*=\\s*\"([0-9.]+)"),
           let height = matchNumber(in: text, pattern: "height\\s*=\\s*\"([0-9.]+)") {
            return CGSize(width: width, height: height)
        }

        if let viewBox = matchViewBox(in: text) {
            return CGSize(width: viewBox.2, height: viewBox.3)
        }

        return nil
    }

    static func matchNumber(in text: String, pattern: String) -> CGFloat? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        guard let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return CGFloat(Double(text[captureRange]) ?? 0)
    }

    static func matchViewBox(in text: String) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let expression = try? NSRegularExpression(pattern: "viewBox\\s*=\\s*\"([0-9.\\-]+)\\s+([0-9.\\-]+)\\s+([0-9.\\-]+)\\s+([0-9.\\-]+)\"") else {
            return nil
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges == 5 else {
            return nil
        }

        let numbers = (1..<5).compactMap { index -> CGFloat? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return CGFloat(Double(text[range]) ?? 0)
        }

        guard numbers.count == 4 else { return nil }
        return (numbers[0], numbers[1], numbers[2], numbers[3])
    }

    static func qualityFromLevel(_ level: Double) -> Double {
        let normalized = max(1, min(10, level))
        let progress = (normalized - 1) / 9
        return 0.94 - progress * 0.76
    }

    static func smallerData(candidate: Data, current: Data?) -> Data {
        guard let current else { return candidate }
        return candidate.count < current.count ? candidate : current
    }

    static func write(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CompressionError.writeFailed(url)
        }
    }

    static func optimizeJPEGInPlace(at url: URL) throws {
        guard let jpegtran = tool(named: "jpegtran") else {
            return
        }
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-opt.jpg")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try runProcess(
            executable: jpegtran,
            arguments: ["-copy", "none", "-optimize", "-progressive", "-outfile", temporaryURL.path, url.path]
        )
        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

    static func tool(named name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    static func runProcess(executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CompressionError.commandFailed(stderr.isEmpty ? "\(executable.lastPathComponent) 执行失败" : stderr)
        }
    }

    static func fileSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}

private extension CGFloat {
    var pixelValue: Int {
        Swift.max(1, Int(self.rounded()))
    }
}

private extension CGImageAlphaInfo {
    var containsAlpha: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return true
        }
    }
}
