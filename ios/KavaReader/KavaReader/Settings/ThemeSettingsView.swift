import SwiftUI

struct ThemeSettingsView: View {
    @Bindable private var settings = ThemeSettings.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 20) {
                ForEach(ThemePalette.allCases) { palette in
                    Button {
                        settings.selected = palette
                    } label: {
                        themeCard(palette)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.text(palette.name))
                    .accessibilityAddTraits(settings.selected == palette ? .isSelected : [])
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("테마 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func themeCard(_ palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    swatch(palette.background, outline: palette.text)
                    swatch(palette.accent, outline: palette.text)
                    swatch(palette.button, outline: palette.text)
                    swatch(palette.text, outline: palette.text)
                }
                .accessibilityHidden(true)
                Spacer(minLength: 4)
                if settings.selected == palette {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 12)
            Text(AppLocalization.text(palette.name))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 112, alignment: .bottomLeading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(settings.selected == palette ? palette.accent : palette.text.opacity(0.12),
                              lineWidth: settings.selected == palette ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func swatch(_ color: Color, outline: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay {
                Circle().strokeBorder(outline.opacity(0.25), lineWidth: 0.5)
            }
    }
}
