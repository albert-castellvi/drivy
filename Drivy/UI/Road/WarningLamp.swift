import SwiftUI

/// A dashboard tell-tale, the way the car itself reports a problem (S3).
///
/// Lit, it is the amber of `caution`; unlit it is `inkMuted` at low opacity, which
/// is what a tell-tale that has nothing to say looks like. The colour carries the
/// state, so the lamp never needs a gradient or a glow (S4).
///
/// Use it in the post-drive summary, one lamp per event kind, with the count as
/// its caption.
struct WarningLamp: View {

    /// The pictogram, an SF Symbol drawn in one colour.
    let systemName: String

    /// `true` reports something: amber. `false` is the quiet state.
    let isLit: Bool

    /// The line under the lamp, normally a count ("1 frenada").
    private let caption: String?

    /// VoiceOver label. With one, the lamp is a single image element; without it,
    /// the caption speaks, and a lamp with no caption is decorative.
    private let label: String?

    /// Height of the pictogram.
    var size: CGFloat = 26

    init(
        systemName: String,
        isLit: Bool = true,
        caption: String? = nil,
        size: CGFloat = 26,
        accessibilityLabel: String? = nil
    ) {
        self.systemName = systemName
        self.isLit = isLit
        self.caption = caption
        self.size = size
        self.label = accessibilityLabel
    }

    var body: some View {
        let lampColor: Color = isLit
            ? Color.drivyCaution
            : Color.drivyInkMuted.opacity(0.45)
        let captionColor: Color = isLit
            ? Color.drivyCautionText
            : Color.drivyInkMuted

        return VStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(lampColor)

            if let caption {
                Text(caption)
                    .font(.drivyKicker)
                    .foregroundStyle(captionColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(WarningLampAccessibility(label: label, hasCaption: caption != nil))
    }
}

/// One announced element when the caller gave words, the caption merged with the
/// lamp when it has one, and nothing at all when the lamp is only decoration.
private struct WarningLampAccessibility: ViewModifier {

    let label: String?

    let hasCaption: Bool

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        } else if hasCaption {
            content
                .accessibilityElement(children: .combine)
        } else {
            content
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Previews

private struct WarningLampPreviewRow: View {

    var body: some View {
        HStack(spacing: 18) {
            WarningLamp(systemName: "exclamationmark", isLit: true, caption: "1 frenada")
            WarningLamp(systemName: "iphone", isLit: false, caption: "Móvil")
        }
        .padding()
        .background(Color.drivyPaper)
    }
}

#Preview("Warning lamps · light") {
    WarningLampPreviewRow()
        .preferredColorScheme(.light)
}

#Preview("Warning lamps · dark") {
    WarningLampPreviewRow()
        .preferredColorScheme(.dark)
}
