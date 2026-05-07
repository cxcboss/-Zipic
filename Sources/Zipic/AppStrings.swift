import Foundation
import TuyaCore

enum AppStrings {
    static var appName: String { ZipicL10n.appName }
    static var alertTitle: String { ZipicL10n.text("处理提醒", "Notice") }
    static var ok: String { ZipicL10n.text("知道了", "OK") }
    static var addImages: String { ZipicL10n.text("添加图片", "Add Images") }
    static var clearList: String { ZipicL10n.text("清空列表", "Clear List") }
    static var recompress: String { ZipicL10n.text("再次压缩", "Compress Again") }
    static var compressing: String { ZipicL10n.text("压缩中…", "Compressing…") }
    static var width: String { ZipicL10n.text("宽度", "Width") }
    static var height: String { ZipicL10n.text("高度", "Height") }
    static var automatic: String { ZipicL10n.text("自动", "Auto") }
    static var keepAspectRatio: String { ZipicL10n.text("保持原始宽高比", "Keep Aspect Ratio") }
    static var resizeSection: String { ZipicL10n.text("尺寸调整", "Resize") }
    static var compressionMethod: String { ZipicL10n.text("压缩方式", "Compression Mode") }
    static var targetSize: String { ZipicL10n.text("目标大小", "Target Size") }
    static var compressionSection: String { ZipicL10n.text("压缩控制", "Compression") }
    static var collapseMore: String { ZipicL10n.text("收起更多设置", "Hide More Settings") }
    static var expandMore: String { ZipicL10n.text("展开更多设置", "Show More Settings") }
    static var outputFormat: String { ZipicL10n.text("目标格式", "Output Format") }
    static var outputSection: String { ZipicL10n.text("输出格式", "Output") }
    static var savePath: String { ZipicL10n.text("保存路径", "Save To") }
    static var outputFolderMissing: String { ZipicL10n.text("尚未选择输出文件夹", "No output folder selected") }
    static var chooseFolder: String { ZipicL10n.text("选择文件夹", "Choose Folder") }
    static var saveSection: String { ZipicL10n.text("保存策略", "Saving") }
    static var dropToCompress: String { ZipicL10n.text("拖入图片开始压缩", "Drop Images to Start Compressing") }
    static var metricDimensions: String { ZipicL10n.text("尺寸", "Dimensions") }
    static var metricOriginal: String { ZipicL10n.text("原始", "Original") }
    static var metricOutput: String { ZipicL10n.text("输出", "Output") }
    static var metricResult: String { ZipicL10n.text("结果", "Result") }
    static var revealInFinder: String { ZipicL10n.text("在访达中显示", "Show in Finder") }
    static var pending: String { ZipicL10n.text("等待处理", "Queued") }
    static var processing: String { ZipicL10n.text("正在压缩", "Processing") }
    static var completed: String { ZipicL10n.text("已完成", "Done") }
    static var failed: String { ZipicL10n.text("处理失败", "Failed") }
    static var outputPending: String { ZipicL10n.text("尚未输出", "Not exported yet") }
    static var addImagesPanelTitle: String { ZipicL10n.text("添加图片", "Add Images") }
    static var chooseOutputFolderTitle: String { ZipicL10n.text("选择输出文件夹", "Choose Output Folder") }
}
