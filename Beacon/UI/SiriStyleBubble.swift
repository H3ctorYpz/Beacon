//
//  SiriStyleBubble.swift
//  Beacon
//
//  Faithful port of Kavsoft SiriBubble (Balaji Venkatesh) — same math,
//  MeshGradient, glassEffect, sizes, and fade. Do not “simplify” this.
//

import SwiftUI

struct SiriStyleBubble: View {
    var hasDynamicIsland: Bool
    var progress: CGFloat
    var buttonSymbol: String
    var hint: String
    var isListening: Bool = false
    @Binding var text: String
    var buttonAction: () -> Void

    var body: some View {
        GeometryReader {
            let size = $0.size
            let extraWidth = size.width - 120
            let fadeProgress = min(max((cappedProgress - 0.3) / 0.7, 0), 1)

            /// Update these values, according to your own needs!
            let midDistance: Float = 0.5
            let row1: [Color] = Array(repeating: .black, count: 3)
            let row2: [Color] = Array(repeating: .black.opacity(0.9), count: 3)
            let row3: [Color] = Array(repeating: .black.opacity(0.3), count: 3)

            ZStack {
                /// Using Mesh instead of Linear Gradient for smooth gradient!
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, midDistance], [0.5, midDistance], [1, midDistance],
                        [0, 1], [0.5, 1], [1, 1],
                    ],
                    colors: row1 + row2 + row3
                )

                /// Content
                HStack(spacing: 10) {
                    TextField(isListening ? "Listening…" : hint, text: $text)
                        .textFieldStyle(.plain)
                        .tint(.white)

                    Button(action: buttonAction) {
                        Image(systemName: buttonSymbol)
                            .symbolEffect(.pulse, isActive: isListening)
                            .foregroundStyle(isListening ? Color.red.opacity(0.95) : Color.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .help(isListening ? "Stop dictation" : "Start dictation")
                }
                .lineLimit(1)
                .font(.title3)
                .compositingGroup()
                .blur(radius: 10 - (10 * fadeProgress))
                .opacity(fadeProgress)
                .padding(.horizontal, 30)
                .disabled(cappedProgress != 1)
            }
            .frame(width: 120 + (extraWidth * cappedProgress))
            .clipShape(clipShape)
            /// Adding Glass Effect
            .glassEffect(.clear.tint(.black.opacity(1 - (0.95 * fadeProgress))), in: clipShape)
            .opacity(hasDynamicIsland ? 1 : fadeProgress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        /// Capsule Size: Minimised: 35 | Expanded: 100
        .frame(height: 35 + (65 * cappedProgress))
        .padding(.horizontal, 15)
        .offset(y: hasDynamicIsland ? 0 : (-100 + (100 * cappedProgress)))
        .environment(\.colorScheme, .dark)
    }

    private var clipShape: Capsule {
        /// Use Concentric, if you wish so!
        Capsule(style: .continuous)
    }

    private var cappedProgress: CGFloat {
        max(min(progress, 1), 0)
    }
}
