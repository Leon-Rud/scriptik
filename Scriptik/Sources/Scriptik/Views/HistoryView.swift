import AppKit
import SwiftUI

struct HistoryView: View {
    @Bindable var history: HistoryManager
    @State private var searchText = ""
    @State private var selectedEntry: HistoryManager.Entry?
    @Environment(\.dismiss) private var dismiss

    private var filtered: [HistoryManager.Entry] {
        if searchText.isEmpty { return history.entries }
        return history.entries.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selectedEntry) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.preview)
                        .font(.body)
                        .lineLimit(2)
                    Text(entry.date, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.content, forType: .string)
                    }
                    Button("Delete", role: .destructive) {
                        history.delete(entry)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search transcriptions")
            .navigationTitle("History")
            .frame(minWidth: 250)
        } detail: {
            if let entry = selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(entry.date, format: .dateTime)
                                .font(.headline)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.content, forType: .string)
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()

                        Text(entry.content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select a transcription",
                    systemImage: "text.alignleft",
                    description: Text("Choose a transcription from the list to view its contents.")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { history.refresh() }
    }
}
