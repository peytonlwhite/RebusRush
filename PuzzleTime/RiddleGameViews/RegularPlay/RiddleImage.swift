//
//  RiddleImage.swift
//  PuzzleTime
//
//  Created by Peyton White on 10/31/25.
//

import SwiftUI

// ---- Riddle Image -------------------------------------------------
struct RiddleImage: View {
    let riddle: Riddle
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass  // ← magic
    
    @State private var pandaCorner: CornerPosition = .random()
    
    // Dynamic size based on device + orientation
    private var imageSize: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 460          // iPad = big and beautiful
        } else if horizontalSizeClass == .regular {   // iPhone in landscape (Plus/Max/Pro Max)
            return 460
        } else {
            return 280          // iPhone portrait (safe and familiar)
        }
    }
    
    private var pandaSize: CGFloat {
        imageSize > 400 ? 120 : 80   // scale panda with image
    }
    
    var body: some View {
        ZStack(alignment: pandaCorner.alignment) {
            // Panda mascot (bigger on iPad!)
            PandaMascotCustom(
                size: pandaSize,
                isWaving: .constant(false),
                peekOffset: 1.0,
                bounce: false
            )
            .rotationEffect(.degrees(pandaCorner.rotation))
            .offset(x: pandaCorner.offsetX * (imageSize / 280),   // scale offsets too!
                    y: pandaCorner.offsetY * (imageSize / 280))
            .zIndex(-1)
            
            // The actual riddle image
            AsyncImage(url: URL(string: riddle.photoUrl)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: imageSize, height: imageSize)
                    
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(glowColor, lineWidth: borderWidth)
                        )
                        .shadow(color: accentColor.opacity(0.5), radius: shadowRadius)
                    
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: imageSize * 0.2))
                        .foregroundColor(.secondary)
                        .frame(width: imageSize, height: imageSize)
                    
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: accentColor.opacity(0.5), radius: shadowRadius)
        }
        .onAppear {
            pandaCorner = .random()
        }
    }
    
    // MARK: - Adaptive Values
    private var cornerRadius: CGFloat { imageSize > 400 ? 28 : 20 }
    private var borderWidth: CGFloat  { imageSize > 400 ? 4 : 3 }
    private var shadowRadius: CGFloat { imageSize > 400 ? 30 : 20 }
    
    private var glowColor: Color { colorScheme == .dark ? .cyan : .yellow }
    private var accentColor: Color { colorScheme == .dark ? .pink : .purple }
    // MARK: - Corner Position Enum
    private enum CornerPosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var alignment: Alignment {
            switch self {
            case .topLeft: return .topLeading
            case .topRight: return .topTrailing
            case .bottomLeft: return .bottomLeading
            case .bottomRight: return .bottomTrailing
            }
        }

        var rotation: Double {
            switch self {
            case .topLeft: return -10
            case .topRight: return 10
            case .bottomLeft: return -10
            case .bottomRight: return 10
            }
        }

        var offsetX: CGFloat {
            switch self {
            case .topLeft, .bottomLeft: return -30
            case .topRight, .bottomRight: return 30
            }
        }

        var offsetY: CGFloat {
            switch self {
            case .topLeft, .topRight: return -30
            case .bottomLeft, .bottomRight: return 30
            }
        }

        static func random() -> CornerPosition {
            allCases.randomElement()!
        }
    }
}

