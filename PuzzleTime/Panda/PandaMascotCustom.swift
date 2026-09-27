//
//  PandaMascotCustom.swift
//  PuzzleTime
//
//  Created by Peyton White on 10/31/25.
//

import SwiftUI


// MARK: - Panda Behind Image
struct PandaBehindImage: View {
    @Binding var pandaPeek: CGFloat
    @Binding var isWaving: Bool // CHANGED: Make isWaving a Binding

    var body: some View {
        GeometryReader { proxy in
            PandaMascotCustom(
                size: proxy.size.width * 0.26,
                isWaving: $isWaving,
                peekOffset: pandaPeek,
                bounce: true
            )
            .position(
                x: proxy.size.width * 0.82,
                y: proxy.size.height * 0.20
            )
            .clipped()
        }
        .ignoresSafeArea()
        .zIndex(-1)
    }
}


struct PandaMascotCustom: View {
    let size: CGFloat
    @Binding var isWaving: Bool // CHANGED: Make isWaving a Binding
    let peekOffset: CGFloat
    let bounce: Bool

    var body: some View {
        ZStack {
            // MARK: - Body (small and chubby)
            Ellipse()
                .fill(Color.white)
                .frame(width: size * 0.6, height: size * 0.45)
                .offset(y: size * 0.35)

            // Arms resting or waving
            if isWaving {
                wavingArmWithBamboo()
            } else {
                arm(offsetX: -size * 0.3, offsetY: size * 0.25, rotation: 20)
                arm(offsetX: size * 0.3, offsetY: size * 0.25, rotation: -20)
            }

            // Legs
            leg(offsetX: -size * 0.15)
            leg(offsetX: size * 0.15)

            // MARK: - Head (big round cute head)
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.9)
                .offset(y: -size * 0.1)

            // Ears
            ear(offsetX: -size * 0.3, offsetY: -size * 0.55)
            ear(offsetX: size * 0.3, offsetY: -size * 0.55)

            // Eye patches
            eyePatch(offsetX: -size * 0.2, offsetY: -size * 0.2)
            eyePatch(offsetX: size * 0.2, offsetY: -size * 0.2)

            // Eyes
            eye(offsetX: -size * 0.2, offsetY: -size * 0.2)
            eye(offsetX: size * 0.2, offsetY: -size * 0.2)

            // Nose
            Triangle()
                .fill(Color.black)
                .frame(width: size * 0.07, height: size * 0.05)
                .offset(y: -size * 0.05)
            
            // Cute Smile (Updated to Capsule)
            mouth()
            
            // Blush
            blush(offsetX: -size * 0.22, offsetY: -size * 0.02)
            blush(offsetX: size * 0.22, offsetY: -size * 0.02)
            
            // Bamboo (resting only)
            if !isWaving {
                bamboo()
                    .rotationEffect(.degrees(25))
                    .offset(x: -size * 0.25, y: size * 0.25)
            }
        }
        .frame(width: size, height: size)
        .offset(y: (1 - peekOffset) * size * 1.4)
        .opacity(peekOffset)
        .scaleEffect(peekOffset)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: peekOffset)
    }

    // MARK: - Ears
    @ViewBuilder
    private func ear(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        Circle()
            .fill(Color.black)
            .frame(width: size * 0.25)
            .offset(x: offsetX, y: offsetY)
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
    }

    // MARK: - Eye Patches
    @ViewBuilder
    private func eyePatch(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        Ellipse()
            .fill(Color.black)
            .frame(width: size * 0.22, height: size * 0.28)
            .rotationEffect(.degrees(10))
            .offset(x: offsetX, y: offsetY)
    }

    // MARK: - Eyes
    @ViewBuilder
    private func eye(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: size * 0.12)
            Circle().fill(Color.black).frame(width: size * 0.06)
                .offset(x: isWaving ? size * 0.01 : 0)
            Circle().fill(Color.white)
                .frame(width: size * 0.025)
                .offset(x: size * 0.015, y: -size * 0.015)
        }
        .offset(x: offsetX, y: offsetY)
    }
    
    // MARK: - Mouth (Updated)
    @ViewBuilder
    private func mouth() -> some View {
        Path { path in
            let smileWidth = size * 0.1
            path.move(to: CGPoint(x: -smileWidth, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: smileWidth, y: 0),
                control: CGPoint(x: 0, y: size * 0.06)
            )
        }
        .stroke(Color.black, lineWidth: size * 0.025)
        .frame(width: size * 0.15, height: size * 0.03) // Slightly wider than nose, thin height
        .offset(x: size * 0.06, y: size * 0.05) // Added x: size * 0.02 for slight right shift
    }
    
    // MARK: - Blush
    @ViewBuilder
    private func blush(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        Circle()
            .fill(Color.pink.opacity(0.4))
            .frame(width: size * 0.09)
            .offset(x: offsetX, y: offsetY)
            .scaleEffect(isWaving ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isWaving)
    }

    // MARK: - Arms
    @ViewBuilder
    private func arm(offsetX: CGFloat, offsetY: CGFloat, rotation: Double) -> some View {
        Ellipse()
            .fill(Color.black)
            .frame(width: size * 0.3, height: size * 0.15)
            .rotationEffect(.degrees(rotation))
            .offset(x: offsetX, y: offsetY)
    }

    // MARK: - Legs
    @ViewBuilder
    private func leg(offsetX: CGFloat) -> some View {
        Ellipse()
            .fill(Color.black)
            .frame(width: size * 0.2, height: size * 0.12)
            .offset(x: offsetX, y: size * 0.45)
    }
    
    // MARK: - Waving Animation
    @ViewBuilder
    private func wavingArmWithBamboo() -> some View {
        arm(offsetX: -size * 0.3, offsetY: -size * 0.05, rotation: 65)
            .rotationEffect(.degrees(isWaving ? 25 : 0), anchor: .topTrailing)
            .offset(x: -size * 0.1, y: -size * 0.1)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatCount(3, autoreverses: true)
                .delay(0.1),
                value: isWaving
            )
        
        bamboo()
            .rotationEffect(.degrees(35))
            .offset(x: -size * 0.42, y: -size * 0.25)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatCount(3, autoreverses: true)
                .delay(0.1),
                value: isWaving
            )
    }
    
    // MARK: - Bamboo
    @ViewBuilder
    private func bamboo() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.02)
                .fill(Color.green.opacity(0.8))
                .frame(width: size * 0.05, height: size * 0.4)

            // Nodes
            ForEach(0..<3) { i in
                Rectangle()
                    .fill(Color.green.opacity(0.5))
                    .frame(width: size * 0.06, height: size * 0.01)
                    .offset(y: CGFloat(i) * size * 0.12 - size * 0.18)
            }
        }
    }
}

// MARK: - Triangle Shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
