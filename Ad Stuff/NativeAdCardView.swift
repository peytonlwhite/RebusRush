import SwiftUI
import GoogleMobileAds

struct NativeAdCardView: View {
    let nativeAd: NativeAd

    var body: some View {
        VStack(spacing: 16) {

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.cyan)
                Text("AD")
                    .font(.caption)
                    .foregroundColor(.cyan)
            }

            VStack(spacing: 10) {
                Text(nativeAd.headline ?? "Sponsored Content")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let body = nativeAd.body {
                    Text(body)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }

            Text("Sponsored")
                .font(.caption)
                .foregroundColor(.cyan)
        }
        .padding()
        .background(Color.black.opacity(0.4))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
    }
}

// --------------------------------------------------
// UIKit BRIDGE (SDK OWNS ALL ASSETS)
// --------------------------------------------------
struct GADNativeAdViewRepresentable: UIViewRepresentable {

    let nativeAd: NativeAd   // GADNativeAd

    func makeUIView(context: Context) -> NativeAdView {

        let nativeAdView = NativeAdView()
        nativeAdView.backgroundColor = .clear
        nativeAdView.nativeAd = nativeAd

        // ==================================================
        // ROOT CONTAINER (CRITICAL — PREVENTS OVERLAP)
        // ==================================================
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        nativeAdView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: nativeAdView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor)
        ])

        // ==================================================
        // MEDIA VIEW (SDK ASSET — ISOLATED)
        // ==================================================
        let mediaView = MediaView()
        mediaView.mediaContent = nativeAd.mediaContent
        mediaView.clipsToBounds = true
        mediaView.translatesAutoresizingMaskIntoConstraints = false

        mediaView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        contentStack.addArrangedSubview(mediaView)
        nativeAdView.mediaView = mediaView

        // ==================================================
        // AD CHOICES (REQUIRED)
        // ==================================================
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.addSubview(adChoicesView)
        nativeAdView.adChoicesView = adChoicesView

        NSLayoutConstraint.activate([
            adChoicesView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 8),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -8)
        ])

        // ==================================================
        // REQUIRED SDK REGISTRATIONS (HIDDEN OK)
        // ==================================================

        // Headline
        let headlineLabel = UILabel()
        headlineLabel.text = nativeAd.headline
        headlineLabel.isHidden = true
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.headlineView = headlineLabel

        // CTA
        let ctaButton = UIButton(type: .system)
        ctaButton.setTitle(nativeAd.callToAction, for: .normal)
        ctaButton.isHidden = true
        nativeAdView.addSubview(ctaButton)
        nativeAdView.callToActionView = ctaButton

        // Icon (optional)
        if let icon = nativeAd.icon {
            let iconView = UIImageView(image: icon.image)
            iconView.isHidden = true
            nativeAdView.addSubview(iconView)
            nativeAdView.iconView = iconView
        }

        // ==================================================
        // SWIFTUI (VISUAL ONLY — BELOW MEDIA)
        // ==================================================
        let hostingController = UIHostingController(
            rootView: NativeAdCardView(nativeAd: nativeAd)
        )

        let swiftUIView = hostingController.view!
        swiftUIView.backgroundColor = .clear
        swiftUIView.isUserInteractionEnabled = false

        contentStack.addArrangedSubview(swiftUIView)

        return nativeAdView
    }

    func updateUIView(_ uiView: NativeAdView, context: Context) {
        uiView.nativeAd = nativeAd
    }
}


extension View {
    @ViewBuilder
    func redactedIf(_ condition: Bool) -> some View {
        if condition {
            self.redacted(reason: .placeholder)
                .opacity(0.6)
                .shimmering()
        } else {
            self.removeRedaction()
        }
    }
}

// Simple Pulse Animation
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    Color.white.opacity(0.3)
                        .mask(Rectangle().fill(
                            LinearGradient(colors: [.clear, .white.opacity(0.4), .clear],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        ))
                        .offset(x: -proxy.size.width + (proxy.size.width * 2 * phase))
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View { self.modifier(Shimmer()) }
    func removeRedaction() -> some View { self.unredacted() }
}




