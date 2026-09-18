import SwiftUI

/// Liquid Glass chip for banners (error / status) on macOS 26+.
struct GlassCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.black.opacity(0.25)), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

struct GlassCardBackground: ViewModifier {
    var corner: CGFloat = 14

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.black.opacity(0.28)), in: .rect(cornerRadius: corner))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

extension View {
    func glassCapsule() -> some View {
        modifier(GlassCapsuleBackground())
    }

    func glassCard(corner: CGFloat = 14) -> some View {
        modifier(GlassCardBackground(corner: corner))
    }
}
