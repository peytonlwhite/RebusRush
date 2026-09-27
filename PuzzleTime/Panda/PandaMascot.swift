//
//  PandaMascot.swift
//  PuzzleTime
//
//  Updated to support SVG → PNG → JPG → emoji fallback
//

import SwiftUI

// MARK: - Panda Mascot (re‑usable)
struct PandaMascot: View {
    // MARK: Public Controls
    let size: CGFloat
    let isWaving: Bool
    let peekOffset: CGFloat   // 0 = hidden, 1 = fully visible
    let bounce: Bool

    // MARK: Private Animation State
    @State private var waveAngle: Angle = .zero
    @State private var bounceOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // ---- 1. Try SVG / PNG from Assets ----
            if let uiImage = UIImage(named: "panda") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

            // ---- 2. Try JPG from main bundle (fallback) ----
            } else if let jpgImage = UIImage(named: "panda.jpg") {
                Image(uiImage: jpgImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)

            // ---- 3. Final emoji fallback ----
            } else {
                Text("🐼")
                    .font(.system(size: size * 0.9))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 1, y: 2)
                    .offset(y: -2) // cute lift
            }

            // ---- Waving Arm (only if enabled) ----
            if isWaving {
                Circle()
                    .fill(Color(.systemGray))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .offset(x: size * 0.28, y: -size * 0.15)
                    .rotationEffect(waveAngle, anchor: .bottom)
                    .shadow(radius: 3)
            }
        }
        .scaleEffect(peekOffset)
        .offset(y: bounce ? bounceOffset : 0)
        .onAppear { startAnimations() }
    }

    // MARK: - Animation Logic
    private func startAnimations() {
        // Wave
        if isWaving {
            withAnimation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
            ) {
                waveAngle = .degrees(-30)
            }
        }

        // Bounce
        if bounce {
            withAnimation(
                .spring(response: 0.6, dampingFraction: 0.7)
                    .repeatForever(autoreverses: true)
            ) {
                bounceOffset = -12
            }
        }
    }
}
