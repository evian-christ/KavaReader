import SwiftUI
import UIKit

enum AppGlassButtonVariant: Equatable {
    case standard
    case primary
}

enum AppGlassButtonConfiguration {
    static func make(title: String? = nil, systemImage: String,
                     variant: AppGlassButtonVariant = .standard, highlighted: Bool = false) -> UIButton.Configuration
    {
        var configuration: UIButton.Configuration = variant == .primary ? .prominentGlass() : .glass()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.indicator = .none
        configuration.contentInsets = .zero

        if variant == .primary {
            configuration.baseBackgroundColor = UIColor(AppTheme.accentFill)
            configuration.baseForegroundColor = UIColor(AppTheme.buttonText)
        } else {
            configuration.baseForegroundColor = UIColor(highlighted ? AppTheme.accent : AppTheme.text)
        }
        return configuration
    }
}

struct AppGlassActionButton: UIViewRepresentable {
    let title: String?
    let systemImage: String
    let size: CGSize
    let isEnabled: Bool
    let isHighlighted: Bool
    let variant: AppGlassButtonVariant
    var expandsToFitTitle = false
    var preservesIconAppearance = false
    let accessibilityLabel: String
    let action: () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(configuration: configuration, primaryAction: nil)
        button.accessibilityLabel = accessibilityLabel
        button.tintAdjustmentMode = preservesIconAppearance ? .normal : .automatic
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.action()
        }, for: .primaryActionTriggered)
        context.coordinator.appearance = appearance
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = isEnabled
        button.tintAdjustmentMode = preservesIconAppearance ? .normal : .automatic
        button.accessibilityLabel = accessibilityLabel
        if context.coordinator.appearance != appearance {
            context.coordinator.appearance = appearance
            button.configuration = configuration
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        guard expandsToFitTitle else { return size }
        let contentWidth = uiView.intrinsicContentSize.width
        return CGSize(width: max(size.width, ceil(contentWidth + 32)), height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var configuration: UIButton.Configuration {
        var configuration = AppGlassButtonConfiguration.make(title: title, systemImage: systemImage,
                                                            variant: variant, highlighted: isHighlighted)
        if preservesIconAppearance {
            configuration.image = UIImage(systemName: systemImage)?.withTintColor(UIColor(AppTheme.text), renderingMode: .alwaysOriginal)
        }
        return configuration
    }

    private var appearance: Appearance {
        Appearance(title: title, systemImage: systemImage, variant: variant, isHighlighted: isHighlighted,
                   preservesIconAppearance: preservesIconAppearance, palette: AppTheme.palette)
    }

    struct Appearance: Equatable {
        let title: String?
        let systemImage: String
        let variant: AppGlassButtonVariant
        let isHighlighted: Bool
        let preservesIconAppearance: Bool
        let palette: ThemePalette
    }

    final class Coordinator {
        var action: () -> Void = {}
        var appearance: Appearance?
    }
}

// Glass labels follow the chosen palette in both light and dark themes.
struct ReaderGlassLabelAppearance: ViewModifier {
    static var foregroundColor: Color {
        AppTheme.text
    }

    func body(content: Content) -> some View {
        content.foregroundStyle(Self.foregroundColor)
    }
}

// Keep a neutral gray tint on iOS 26 without Regular glass's automatic
// light/dark material switching or an opaque backing over the artwork.
struct ReaderGlassButtonAppearance: ViewModifier {
    private let grayTint = Color(white: 0.35).opacity(0.65)

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.glass(.clear.tint(grayTint)))
        }
    }
}
