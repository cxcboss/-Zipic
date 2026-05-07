import Foundation

public enum ZipicL10n {
    public static var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    public static var appName: String {
        text("图缩", "Zipic")
    }

    public static var dropFormats: String {
        text("支持 JPG / PNG / GIF / SVG / WebP", "Supports JPG / PNG / GIF / SVG / WebP")
    }

    public static var memoryMessage: String {
        text("正在逐张压缩并及时释放内存", "Compressing one image at a time to keep memory usage low")
    }

    public static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }

    public static func imageCount(_ count: Int) -> String {
        isChinese ? "共 \(count) 张图片" : "\(count) image\(count == 1 ? "" : "s")"
    }

    public static func savings(_ percent: Int) -> String {
        isChinese ? "节省 \(percent)%" : "Saved \(percent)%"
    }
}
