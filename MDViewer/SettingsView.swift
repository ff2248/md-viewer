import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = "auto"
    @AppStorage(SettingsKey.hardBreaks) private var hardBreaks = RenderOptions.defaults.hardBreaks
    @AppStorage(SettingsKey.showFrontMatter) private var showFrontMatter = RenderOptions.defaults.showFrontMatter
    @AppStorage(SettingsKey.externalEditor) private var externalEditor = RenderOptions.defaultExternalEditor
    @AppStorage(SettingsKey.bodyFontSize) private var bodyFontSize = RenderOptions.defaults.bodyFontSize
    @AppStorage(SettingsKey.codeFontSize) private var codeFontSize = RenderOptions.defaults.codeFontSize
    @AppStorage(SettingsKey.restoreTabsEnabled) private var restoreTabsEnabled = true

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            Toggle("Single newline as line break", isOn: $hardBreaks)
            Toggle("Show YAML front matter", isOn: $showFrontMatter)
            Toggle("Restore tabs on launch", isOn: $restoreTabsEnabled)

            LabeledContent("External Editor") {
                Menu(editorDisplayName) {
                    ForEach(GlobalSettings.installedRecommendedEditors(), id: \.path) { editor in
                        Button(editor.displayName) { externalEditor = editor.path }
                    }
                    Divider()
                    Button("Choose another…") { pickEditor() }
                }
            }

            LabeledContent("Body Font Size") {
                HStack {
                    Slider(value: $bodyFontSize, in: RenderOptions.bodyFontSizeRange, step: 1)
                    Text("\(Int(bodyFontSize))px")
                        .monospacedDigit()
                        .frame(minWidth: 32, alignment: .trailing)
                }
            }

            LabeledContent("Code Font Size") {
                HStack {
                    Slider(value: $codeFontSize, in: RenderOptions.codeFontSizeRange, step: 1)
                    Text("\(Int(codeFontSize))px")
                        .monospacedDigit()
                        .frame(minWidth: 32, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in
            GlobalSettings.applyAppearance(newValue)
        }
    }

    private var editorDisplayName: String {
        let url = URL(filePath: externalEditor)
        return url.deletingPathExtension().lastPathComponent
    }

    private func pickEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an application to edit Markdown files"
        if panel.runModal() == .OK, let url = panel.url {
            externalEditor = url.path
        }
    }
}
