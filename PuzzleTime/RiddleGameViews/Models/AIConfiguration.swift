import Foundation
import FirebaseRemoteConfig

enum AIConfiguration {
    static let defaultModel = "gemini-3.5-flash"
    static let modelKey = "answer_model_name"

    static func configure() {
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        settings.fetchTimeout = 10
        config.configSettings = settings
        config.setDefaults([modelKey: defaultModel as NSString])
    }

    static func refresh() async {
        _ = try? await RemoteConfig.remoteConfig().fetchAndActivate()
    }

    static var modelName: String {
        validatedModel(RemoteConfig.remoteConfig()[modelKey].stringValue)
    }

    static func validatedModel(_ value: String) -> String {
        guard value.count <= 100,
              value.range(of: #"^gemini-[a-z0-9]+(?:[.-][a-z0-9]+)*$"#, options: .regularExpression) != nil
        else { return defaultModel }
        return value
    }
}
