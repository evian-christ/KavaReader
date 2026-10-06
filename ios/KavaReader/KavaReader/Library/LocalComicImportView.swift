import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LocalComicPicker: UIViewControllerRepresentable {
    let folder: Bool
    let completion: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = folder ? [.folder] : [.zip, UTType(filenameExtension: "cbz") ?? .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = !folder
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion([]) }
    }
}

nonisolated enum LocalComicImport {
    enum Failure: LocalizedError {
        case unsupportedFormat
        var errorDescription: String? { AppLocalization.text("CBZ·ZIP 파일만 불러올 수 있습니다.") }
    }
    struct File: Sendable { let url: URL; let group: String? }
    static func supports(_ url: URL) -> Bool {
        ["cbz", "zip"].contains(url.pathExtension.lowercased())
    }
    static func files(in urls: [URL]) throws -> [File] {
        var files: [File] = []
        for url in urls {
            try Task.checkCancellation()
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                guard let enumerator = FileManager.default.enumerator(at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
                for case let file as URL in enumerator {
                    try Task.checkCancellation()
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true,
                          supports(file) else { continue }
                    // One folder corresponds to one work; nested folders retain their path in the name.
                    let parent = file.deletingLastPathComponent()
                    let relative = parent.path == url.path ? url.lastPathComponent :
                        String(parent.path.dropFirst(url.path.count + 1)).replacingOccurrences(of: "/", with: " · ")
                    files.append(File(url: file, group: relative))
                }
            } else if supports(url) {
                files.append(File(url: url, group: nil))
            }
        }
        return files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
}

struct LocalComicManagementView: View {
    let comic: LocalComic
    @EnvironmentObject private var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var deleteConfirmation = false
    @State private var resetConfirmation = false
    @State private var message: String?
    @State private var target: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("작품 이름") {
                    TextField("작품 이름", text: $title)
                    Button("이름 저장") { perform { try await LocalComicStore.shared.edit(comic.id, title: title) } }
                }
                Section("권 목록") {
                    ForEach(comic.volumes) { volume in
                        HStack {
                            Text(volume.title)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: volume.bytes, countStyle: .file))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
                if library.localComics.count > 1 {
                    Section("작품 합치기") {
                        Picker("합칠 작품", selection: $target) {
                            Text("작품 선택").tag(nil as UUID?)
                            ForEach(library.localComics.filter { $0.id != comic.id }) { other in
                                Text(other.title).tag(Optional(other.id))
                            }
                        }
                        Button("선택한 작품으로 권 이동") {
                            if let target { perform { try await LocalComicStore.shared.merge(comic.id, into: target) } }
                        }.disabled(target == nil)
                    }
                }
                Section("읽기 상태") {
                    Button("완독으로 표시") { perform { try await LocalComicStore.shared.edit(comic.id, read: true) } }
                    Button("읽기 기록 초기화", role: .destructive) { resetConfirmation = true }
                }
                Section {
                    Button("기기에서 작품 삭제", role: .destructive) { deleteConfirmation = true }
                } footer: { Text("가져온 원본 파일은 삭제하지 않습니다.") }
                if let message { Text(message).foregroundStyle(.orange) }
            }
            .buttonStyle(.glass)
            .navigationTitle("파일 관리")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppGlassActionButton(title: nil, systemImage: "xmark", size: CGSize(width: 38, height: 38),
                        isEnabled: true, isHighlighted: false, variant: .standard,
                        accessibilityLabel: AppLocalization.text("닫기")) { dismiss() }
                }
            }
            .confirmationDialog("기기에 보관한 작품과 읽기 기록을 삭제할까요?", isPresented: $deleteConfirmation,
                                titleVisibility: .visible) {
                Button("삭제", role: .destructive) { perform { try await LocalComicStore.shared.delete(comic.id) } }
            }
            .confirmationDialog("읽기 기록을 초기화할까요?", isPresented: $resetConfirmation, titleVisibility: .visible) {
                Button("읽기 기록 초기화", role: .destructive) { perform { try await LocalComicStore.shared.edit(comic.id, read: false) } }
            }
            .onAppear { title = comic.title }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action(); await library.reloadLocalComics(); dismiss() }
            catch { message = error.localizedDescription }
        }
    }
}
