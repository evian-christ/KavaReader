import MessageUI
import SwiftUI

struct SupportView: View {
    @Environment(\.openURL) private var openURL
    @State private var message = ""
    @State private var showMailComposer = false
    @State private var errorMessage: String?
    @FocusState private var isMessageFocused: Bool

    private let recipient = "kavareader@gmail.com"

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsCard(title: "문의 내용") {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $message)
                            .font(.body)
                            .foregroundStyle(AppTheme.text)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .focused($isMessageFocused)
                            .accessibilityLabel(Text("문의 내용"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                        if message.isEmpty {
                            Text("문의 내용을 입력해 주세요.")
                                .font(.body)
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(.horizontal, 17)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isMessageFocused ? AppTheme.accent : AppTheme.secondaryText.opacity(0.5),
                                          lineWidth: isMessageFocused ? 2 : 1)
                            .allowsHitTesting(false)
                    }
                }

                Text("제출하면 메일 작성창이 열립니다. 작성창에서 전송을 눌러 문의를 보내 주세요.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)

                AppGlassActionButton(title: AppLocalization.text("제출"),
                                     systemImage: "paperplane",
                                     size: CGSize(width: 140, height: 44),
                                     isEnabled: !trimmedMessage.isEmpty,
                                     isHighlighted: false,
                                     variant: .primary,
                                     expandsToFitTitle: true,
                                     accessibilityLabel: AppLocalization.text("제출")) {
                    submit()
                }
                .frame(height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("문의 이메일")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(verbatim: recipient)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle("고객지원")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMailComposer) {
            SupportMailComposer(recipient: recipient,
                                subject: AppLocalization.text("Kava 고객지원 문의"),
                                messageBody: trimmedMessage) { result, failed in
                showMailComposer = false
                if failed || result == .failed {
                    errorMessage = "메일을 보내지 못했습니다. 입력한 내용은 유지됩니다. 다시 시도해 주세요."
                } else if result == .sent {
                    message = ""
                }
            }
            .ignoresSafeArea()
        }
        .alert("문의 전송 안내", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { errorMessage = nil }
        } message: {
            Text(AppLocalization.text(errorMessage ?? ""))
        }
    }

    private func submit() {
        guard !trimmedMessage.isEmpty else { return }
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
            return
        }

        // Other mail apps can handle mailto when Apple Mail is not configured.
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: AppLocalization.text("Kava 고객지원 문의")),
            URLQueryItem(name: "body", value: trimmedMessage),
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            errorMessage = "메일 작성창을 열 수 없습니다. 메일 앱을 설정하거나 문의 이메일로 직접 보내 주세요."
            return
        }
        openURL(url) { accepted in
            if !accepted {
                errorMessage = "메일 작성창을 열 수 없습니다. 메일 앱을 설정하거나 문의 이메일로 직접 보내 주세요."
            }
        }
    }
}

private struct SupportMailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let messageBody: String
    let onFinish: (MFMailComposeResult, Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(messageBody, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, Bool) -> Void

        init(onFinish: @escaping (MFMailComposeResult, Bool) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result, error != nil)
        }
    }
}
