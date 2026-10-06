import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String?
    let footer: String?
    let horizontalInset: CGFloat
    @ViewBuilder let content: Content

    init(title: String? = nil, footer: String? = nil, horizontalInset: CGFloat = 16,
         @ViewBuilder content: () -> Content)
    {
        self.title = title
        self.footer = footer
        self.horizontalInset = horizontalInset
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(LocalizedStringKey(title))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, horizontalInset)
            }

            VStack(spacing: 0) {
                content
            }
            .labelStyle(SettingsIconLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)

            if let footer {
                Text(LocalizedStringKey(footer))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, horizontalInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 28)
                .foregroundStyle(AppTheme.accent)
            configuration.title
        }
    }
}

struct SettingsCardDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 16)
    }
}
