import Testing
import CoreGraphics
import Foundation
import ImageIO
@testable import TuyaCore

@Test func jpegTargetSizeCompressionProducesOutput() async throws {
    let tempDirectory = try temporaryDirectory(named: "jpeg")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let sourceURL = tempDirectory.appendingPathComponent("sample.jpg")
    try makeJPEGSource(at: sourceURL, size: CGSize(width: 1400, height: 900), quality: 0.96)

    let result = try await CompressionEngine.compress(
        CompressionRequest(
            inputURL: sourceURL,
            originalURL: sourceURL,
            settings: CompressionSettings(
                compressionMode: .targetSize,
                targetSizeKB: 120,
                outputFormat: .jpg,
                saveMode: .originalFolder,
                outputSuffix: "-out"
            )
        )
    )

    #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
    #expect(result.outputSize <= 130 * 1024)
    #expect(result.pixelWidth == 1400)
    #expect(result.pixelHeight == 900)
}

@Test func svgOptimizationShrinksAndRewritesDimensions() async throws {
    let tempDirectory = try temporaryDirectory(named: "svg")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let sourceURL = tempDirectory.appendingPathComponent("vector.svg")
    let source = """
    <!--comment-->
    <svg width="1200" height="800" viewBox="0 0 1200 800" xmlns="http://www.w3.org/2000/svg">
        <rect width="1200" height="800" fill="#ffffff"></rect>
        <circle cx="600" cy="400" r="180" fill="#5b9df9"></circle>
    </svg>
    """
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)

    let result = try await CompressionEngine.compress(
        CompressionRequest(
            inputURL: sourceURL,
            originalURL: sourceURL,
            settings: CompressionSettings(
                maxWidth: 400,
                keepAspectRatio: true,
                compressionMode: .quality,
                outputFormat: .original,
                saveMode: .originalFolder,
                outputSuffix: "-optimized"
            )
        )
    )

    let output = try String(contentsOf: result.destinationURL, encoding: .utf8)
    #expect(result.destinationURL.pathExtension == "svg")
    #expect(result.outputSize < result.originalSize)
    #expect(output.contains("width=\"400\""))
    #expect(output.contains("height=\"266\"") || output.contains("height=\"267\""))
}

private func temporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ZipicTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeJPEGSource(at url: URL, size: CGSize, quality: CGFloat) throws {
    let width = Int(size.width)
    let height = Int(size.height)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    for row in 0..<height {
        let progress = CGFloat(row) / CGFloat(height)
        context.setFillColor(CGColor(red: progress, green: 0.3, blue: 1 - progress, alpha: 1))
        context.fill(CGRect(x: 0, y: row, width: width, height: 1))
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
    for index in stride(from: 0, to: width, by: 40) {
        context.fillEllipse(in: CGRect(x: index, y: (index / 3) % height, width: 80, height: 80))
    }

    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: quality
    ] as CFDictionary)
    CGImageDestinationFinalize(destination)
    try (data as Data).write(to: url, options: .atomic)
}
