import SwiftUI
import UIKit

/// Soft monochrome shapes behind the content; Liquid Glass over a flat color
/// has nothing to bend, so this gives it depth without adding color.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            Circle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 440, height: 440)
                .blur(radius: 90)
                .offset(x: -150, y: -280)
            Circle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 170, y: 60)
            Circle()
                .fill(Color.primary.opacity(0.05))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -90, y: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Small version of the app icon.
struct AppGlyph: View {
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color.black)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}

/// Mimics an iOS notification banner.
struct NotificationPreview: View {
    let content: Rendered

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppGlyph()
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(content.title.isEmpty ? "Pulso" : content.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("ahora")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(content.body)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

extension View {
    /// "Listo" above number pads, which have no return key.
    func keyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                    )
                }
                .fontWeight(.semibold)
            }
        }
    }
}
