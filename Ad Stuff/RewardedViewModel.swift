import Foundation
import SwiftUI
import GoogleMobileAds
import Combine
import AppTrackingTransparency

@MainActor
class RewardedViewModel: NSObject, ObservableObject {
   
    // MARK: — Published UI State
    @Published var coins: Int = 0
    @Published var isBannerAdLoaded: Bool = false
    @Published var isTrackingAuthorized: Bool = false
    @Published var isInterstitialLoaded: Bool = false
    @Published var nativeAds: [NativeAd] = []  // Queue of loaded native ads
    
    // MARK: — Internal Ad Objects
    private var rewardedAd: RewardedAd?
    private var bannerView: BannerView?
    private var interstitialAd: InterstitialAd? //ca-app-pub-4618134083822244/4356776811
    private var adLoader: AdLoader?
    
    // Reward handling
    private var onRewardHandler: ((Int) -> Void)?
    private var onDismissHandler: (() -> Void)?
    private var didEarnReward = false
    private var isLoadingNativeAd = false

    // Singleton
    static let shared = RewardedViewModel()
    
    override init() {
        super.init()
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        setupATTListener()
        // ✅ LOAD IMMEDIATELY
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.loadNativeAds(count: 5)
        }
    }
    
    // MARK: — NATIVE ADS
    private lazy var nativeAdUnitID: String = {
        adUnitID(
            testID: "ca-app-pub-3940256099942544/3986624511",  // Official Google test native
            liveID: "ca-app-pub-4618134083822244/3228539738"   // Your real native unit
        )
    }()
    
    private var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    }
    

    
    func ensureAdsAreLoaded() {
        // If we have fewer than 2 ads waiting, load more
        if nativeAds.count < 5 && !isLoadingNativeAd {
                loadNativeAds(count: 5 - nativeAds.count)
            }
    }

    // Helper to get a specific ad for a specific position (PREVENTS CRASHES)
    func getAd(at index: Int) -> NativeAd? {
        guard index < nativeAds.count else { return nil }
        return nativeAds[index]
    }
    
    //ca-app-pub-4618134083822244/3228539738 - real
    func loadNativeAds(count: Int = 1) {
        guard !isLoadingNativeAd else {
                print("⏸️ Native ad load already in progress")
            return
        }
        
        guard let rootVC = rootViewController else {
            print("⏳ Root VC not ready, retrying native ads...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.loadNativeAds(count: count)
            }
            return
        }
        
        isLoadingNativeAd = true
        
        let options = MultipleAdsAdLoaderOptions()
        options.numberOfAds = count
        
        let loader = AdLoader(
            adUnitID: nativeAdUnitID,
            rootViewController: rootVC,
            adTypes: [.native],
            options: [options]
        )

        loader.delegate = self
        self.adLoader = loader // keep strong reference

        let request = Request()
        if !isTrackingAuthorized {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }

        print("🚀 Loading \(count) native ad(s)...")
        loader.load(request)
    }

    
    func preloadNextNativeAds() {
        let currentCount = nativeAds.count
        let target = 5  // Buffer for longer carousels
        let needed = max(target - currentCount, 0)
        
        print("🔄 Preloading: queue = \(currentCount), need \(needed)")
        
        if needed > 0 && !isLoadingNativeAd {
            loadNativeAds(count: needed)
        }
    }
    
    // NEW: Load Standard Interstitial (every 3 scrolls)
    func loadInterstitial() async -> Bool {
        let adUnitID = adUnitID(
            testID: "ca-app-pub-3940256099942544/4411468910",  // OFFICIAL Google test interstitial iOS
            liveID: "ca-app-pub-4618134083822244/4356776811"  // Create in AdMob: Apps > Your App > Interstitial
        )
        
        let request = Request()
        if !isTrackingAuthorized {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }
        
        do {
            interstitialAd = try await InterstitialAd.load(with: adUnitID, request: request)
            interstitialAd?.fullScreenContentDelegate = self
            isInterstitialLoaded = true
            print("✅ Interstitial loaded: \(adUnitID)")
            return true
        } catch {
            print("❌ Interstitial failed: \(error)")
            return false
        }
    }

 
    func showInterstitial(onDismiss: @escaping () -> Void) {
        guard let ad = interstitialAd,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            print("⚠️ No interstitial or VC")
            onDismiss()
            return
        }
        
        let presenter = rootVC.presentedViewController ?? rootVC
        interstitialAd = nil
        isInterstitialLoaded = false
        
        ad.present(from: presenter)
        
        self.onDismissHandler = onDismiss
    }
    
    
    
    
    private func adUnitID(testID: String, liveID: String) -> String {
#if DEBUG || targetEnvironment(simulator)
        return testID
#endif
        let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        return isTestFlight ? testID : liveID
    }
    
    // MARK: — REWARDED AD LOADING
    func loadRewardedAd() async -> Bool {
        
        //live - ca-app-pub-4618134083822244/2278946499
        let adUnitID = adUnitID(
            testID: "ca-app-pub-3940256099942544/1712485313",
            liveID: "ca-app-pub-4618134083822244/2278946499"
        )
        
        let request = Request()
        
        if !isTrackingAuthorized {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            print("ℹ️ Rewarded Ad: Non-personalized")
        } else {
            print("ℹ️ Rewarded Ad: Personalized")
        }

        do {
            let ad = try await RewardedAd.load(with: adUnitID, request: request)
            rewardedAd = ad
            ad.fullScreenContentDelegate = self
            print("✅ Rewarded ad loaded. Using ID: \(adUnitID)")
            return true

        } catch {
            print("❌ Failed to load rewarded ad:", error.localizedDescription)
            return false
        }
    }

    // MARK: — SHOW REWARDED AD
    func showAd(
        completion: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard let ad = rewardedAd else {
            print("⚠️ No rewarded ad ready.")
            onDismiss()
            return
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            print("⚠️ No presenting view controller.")
            onDismiss()
            return
        }

        let presenter = rootVC.presentedViewController ?? rootVC

        didEarnReward = false
        onRewardHandler = completion
        onDismissHandler = onDismiss

        ad.present(from: presenter) { [weak self] in
            guard let self = self else { return }
            let rewardAmount = Int(truncating: ad.adReward.amount)
            print("🎉 User earned reward:", rewardAmount)

            self.didEarnReward = true
            self.onRewardHandler?(rewardAmount)
            self.onRewardHandler = nil
        }
    }

    // MARK: — BANNER AD LOADING
    func loadBannerAd() {
        //live - ca-app-pub-4618134083822244/5912011694
        let bannerID = adUnitID(
            testID: "ca-app-pub-3940256099942544/2934735716",
            liveID: "ca-app-pub-4618134083822244/5912011694"
        )

        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = bannerID
        banner.delegate = self

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            banner.rootViewController = window.rootViewController
        }

        let request = Request()
        if !isTrackingAuthorized {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            print("ℹ️ Banner Ad: Non-personalized")
        } else {
            print("ℹ️ Banner Ad: Personalized")
        }

        banner.load(request)
        bannerView = banner
    }

    func getBannerView() -> BannerView? {
        return bannerView
    }
    
 
  
    
    // MARK: — ATT LISTENER
    private func setupATTListener() {
        NotificationCenter.default.addObserver(
            forName: .attAuthorizationStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isTrackingAuthorized = ATTStatusManager.shared.authorizationStatus == .authorized
                
                Task { await self.loadRewardedAd() }
                self.loadBannerAd()
                
                //Task { await loadInterstitial() }
                self.loadNativeAds(count: 5)
            }
        }
    }
    
   
}

// MARK: - Ad Loader Delegate
extension RewardedViewModel: AdLoaderDelegate, NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("✅ Native ad loaded")
        nativeAds.append(nativeAd)
        // DO NOT clear isLoadingNativeAd here when using multiple ads
        preloadNextNativeAds()
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("❌ Native ad load failed: \(error.localizedDescription)")
        isLoadingNativeAd = false
        self.adLoader = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.preloadNextNativeAds()
        }
    }
    
    func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        print("ℹ️ Native ad batch finished")
        isLoadingNativeAd = false  // ← Clear flag only when entire batch is done
        preloadNextNativeAds()
    }
}

// MARK: — FULL SCREEN CONTENT DELEGATE
extension RewardedViewModel: FullScreenContentDelegate {
    
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("ℹ️ Fullscreen ad dismissed (rewarded or interstitial)")
        
        // Call dismiss handler for both ad types
        onDismissHandler?()
        onDismissHandler = nil
        
        // Reload both ad types for next time
        Task { await loadInterstitial() }
        Task { await loadRewardedAd() }
        
        rewardedAd = nil
    }


    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        print("❌ Rewarded failed to present:", error.localizedDescription)
        onDismissHandler?()
        rewardedAd = nil
        Task { await loadRewardedAd() }
        Task { await loadInterstitial() }
    }
}

// MARK: — BANNER DELEGATE
extension RewardedViewModel: BannerViewDelegate {

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        print("✅ Banner loaded")
        isBannerAdLoaded = true
    }

    func bannerView(
        _ bannerView: BannerView,
        didFailToReceiveAdWithError error: Error
    ) {
        print("❌ Banner failed:", error.localizedDescription)
        isBannerAdLoaded = false
    }
}
