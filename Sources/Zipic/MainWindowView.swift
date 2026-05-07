import AppKit
import SwiftUI
import TuyaCore

struct MainWindowView: View {
    @ObservedObject var state: AppState
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            contentArea
            Divider()
            actionBar
            Divider()
            settingsArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { items, _ in
            state.importFiles(with: items)
            return true
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .alert(AppStrings.alertTitle, isPresented: Binding(
            get: { state.alertMessage != nil },
            set: { if !$0 { state.alertMessage = nil } }
        )) {
            Button(AppStrings.ok, role: .cancel) {
                state.alertMessage = nil
            }
        } message: {
            Text(state.alertMessage ?? "")
        }
    }

    private var contentArea: some View {
        ZStack {
            if state.jobs.isEmpty {
                EmptyDropZone(isTargeted: isDropTarget, subtitle: state.summaryText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(state.jobs) { item in
                            JobRowView(item: item, onReveal: {
                                state.revealOutput(of: item)
                            })
                        }
                    }
                    .padding(20)
                }
                .overlay(alignment: .center) {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
                            .padding(32)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 18) {
            Button {
                state.openImporter()
            } label: {
                Label(AppStrings.addImages, systemImage: "plus.square")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.link)

            Text(state.summaryText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Button(AppStrings.clearList) {
                state.clearJobs()
            }
            .disabled(state.jobs.isEmpty || state.isCompressing)

            Button(state.isCompressing ? AppStrings.compressing : AppStrings.recompress) {
                state.recompressAll()
            }
            .disabled(state.jobs.isEmpty || state.isCompressing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var settingsArea: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            LabeledInput(title: AppStrings.width, text: state.optionalIntBinding(\.maxWidth), placeholder: AppStrings.automatic)
                            LabeledInput(title: AppStrings.height, text: state.optionalIntBinding(\.maxHeight), placeholder: AppStrings.automatic)
                        }

                        Toggle(AppStrings.keepAspectRatio, isOn: $state.settings.keepAspectRatio)
                            .toggleStyle(.checkbox)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(AppStrings.resizeSection, systemImage: "aspectratio")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        RadioRow(
                            title: AppStrings.compressionMethod,
                            options: CompressionMode.allCases,
                            selection: $state.settings.compressionMode
                        ) { mode in
                            mode.displayName
                        }

                        if state.settings.compressionMode == .quality {
                            VStack(alignment: .leading, spacing: 10) {
                                Slider(value: $state.settings.qualityLevel, in: 1...10, step: 1)
                                HStack {
                                    Text("1")
                                    Spacer()
                                    Text("\(Int(state.settings.qualityLevel))")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("10")
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            }
                        } else {
                            LabeledInput(title: AppStrings.targetSize, text: state.intBinding(\.targetSizeKB), placeholder: "KB", suffix: "KB")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(AppStrings.compressionSection, systemImage: "dial.medium")
                }
            }
            .padding(.horizontal, 20)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    state.showExtendedSettings.toggle()
                }
            } label: {
                Label(state.showExtendedSettings ? AppStrings.collapseMore : AppStrings.expandMore, systemImage: state.showExtendedSettings ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if state.showExtendedSettings {
                VStack(spacing: 16) {
                    GroupBox {
                        RadioRow(
                            title: AppStrings.outputFormat,
                            options: OutputFormat.allCases,
                            selection: $state.settings.outputFormat
                        ) { format in
                            format.displayName
                        }
                    } label: {
                        Label(AppStrings.outputSection, systemImage: "photo")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            RadioRow(
                                title: AppStrings.savePath,
                                options: SaveMode.allCases,
                                selection: $state.settings.saveMode
                            ) { mode in
                                mode.displayName
                            }

                            if state.settings.saveMode == .customFolder {
                                HStack(spacing: 12) {
                                    Text(state.settings.customDirectory?.path ?? AppStrings.outputFolderMissing)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                    Button(AppStrings.chooseFolder) {
                                        state.chooseCustomFolder()
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(AppStrings.saveSection, systemImage: "folder")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 18)
    }
}

private struct EmptyDropZone: View {
    let isTargeted: Bool
    let subtitle: String

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 10])
                    )
                    .frame(width: 170, height: 140)
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            }
            Text(AppStrings.dropToCompress)
                .font(.system(size: 24, weight: .medium))
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}

private struct JobRowView: View {
    @ObservedObject var item: CompressionItem
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            preview
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.sourceURL.lastPathComponent)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(item.state.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.state.tint)
                }

                HStack(spacing: 18) {
                    MetricLabel(title: AppStrings.metricDimensions, value: item.dimensionsText)
                    MetricLabel(title: AppStrings.metricOriginal, value: item.originalSizeText)
                    MetricLabel(title: AppStrings.metricOutput, value: item.outputSizeText)
                    MetricLabel(title: AppStrings.metricResult, value: item.savedText)
                }

                Text(item.destinationText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let note = item.noteText, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if item.outputURL != nil {
                    Button(AppStrings.revealInFinder, action: onReveal)
                        .font(.system(size: 12))
                        .buttonStyle(.link)
                }

                if case .failed(let message) = item.state {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let preview = item.preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MetricLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }
}

private struct LabeledInput: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var suffix: String?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14))
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RadioRow<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.system(size: 14))
                .frame(width: 72, alignment: .leading)

            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == option ? Color.accentColor : Color.secondary)
                        Text(label(option))
                            .foregroundStyle(.primary)
                    }
                    .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }
}
