import Foundation
import protocol Yosemite.StoresManager

/// Content for a local notification to be converted to `UNNotificationContent`.
struct LocalNotification {
    let title: String
    let body: String
    let scenario: Scenario
    let actions: CategoryActions?
    let userInfo: [AnyHashable: Any]

    /// A category of actions in a notification.
    struct CategoryActions {
        let category: Category
        let actions: [Action]
    }

    /// The scenario for the local notification.
    /// Its raw value is used for the identifier of a local notification and also the event property for analytics.
    enum Scenario {
        case storeCreationComplete
        case oneDayAfterStoreCreationNameWithoutFreeTrial(storeName: String)
        case oneDayBeforeFreeTrialExpires(siteID: Int64, expiryDate: Date)
        case oneDayAfterFreeTrialExpires(siteID: Int64)
        case sixHoursAfterFreeTrialSubscribed(siteID: Int64)
        case freeTrialSurvey24hAfterFreeTrialSubscribed(siteID: Int64)
        case threeDaysAfterStillExploring(siteID: Int64)

        var identifier: String {
            switch self {
            case .storeCreationComplete:
                return "store_creation_complete"
            case .oneDayAfterStoreCreationNameWithoutFreeTrial:
                return Identifier.oneDayAfterStoreCreationNameWithoutFreeTrial
            case let .oneDayBeforeFreeTrialExpires(siteID, _):
                return Identifier.Prefix.oneDayBeforeFreeTrialExpires + "\(siteID)"
            case .oneDayAfterFreeTrialExpires(let siteID):
                return Identifier.Prefix.oneDayAfterFreeTrialExpires + "\(siteID)"
            case let .sixHoursAfterFreeTrialSubscribed(siteID):
                return Identifier.Prefix.sixHoursAfterFreeTrialSubscribed + "\(siteID)"
            case let .freeTrialSurvey24hAfterFreeTrialSubscribed(siteID):
                return Identifier.Prefix.freeTrialSurvey24hAfterFreeTrialSubscribed + "\(siteID)"
            case let .threeDaysAfterStillExploring(siteID):
                return Identifier.Prefix.threeDaysAfterStillExploring + "\(siteID)"
            }
        }

        enum Identifier {
            enum Prefix {
                static let oneDayBeforeFreeTrialExpires = "one_day_before_free_trial_expires"
                static let oneDayAfterFreeTrialExpires = "one_day_after_free_trial_expires"
                static let sixHoursAfterFreeTrialSubscribed = "six_hours_after_free_trial_subscribed"
                static let freeTrialSurvey24hAfterFreeTrialSubscribed = "free_trial_survey_24h_after_free_trial_subscribed"
                static let threeDaysAfterStillExploring = "three_days_after_still_exploring"
            }
            static let oneDayAfterStoreCreationNameWithoutFreeTrial = "one_day_after_store_creation_name_without_free_trial"
        }

        /// Helper method to remove postfix from notification identifiers if needed.
        static func identifierForAnalytics(_ identifier: String) -> String {
            if identifier.hasPrefix(Identifier.Prefix.oneDayBeforeFreeTrialExpires) {
                return Identifier.Prefix.oneDayBeforeFreeTrialExpires
            } else if identifier.hasPrefix(Identifier.Prefix.oneDayAfterFreeTrialExpires) {
                return Identifier.Prefix.oneDayAfterFreeTrialExpires
            } else if identifier.hasPrefix(Identifier.Prefix.sixHoursAfterFreeTrialSubscribed) {
                return Identifier.Prefix.sixHoursAfterFreeTrialSubscribed
            } else if identifier.hasPrefix(Identifier.Prefix.freeTrialSurvey24hAfterFreeTrialSubscribed) {
                return Identifier.Prefix.freeTrialSurvey24hAfterFreeTrialSubscribed
            } else if identifier.hasPrefix(Identifier.Prefix.threeDaysAfterStillExploring) {
                return Identifier.Prefix.threeDaysAfterStillExploring
            }
            return identifier
        }
    }

    /// The category of actions for a local notification.
    enum Category: String {
        case storeCreation
    }

    /// The action type in a local notification.
    enum Action: String {
        // TODO: add any custom action if needed
        case none

        /// The title of the action in a local notification.
        var title: String {
            return ""
        }
    }

    /// Holds `userInfo` dictionary keys
    enum UserInfoKey {
        static let storeName = "storeName"
        static let isIAPAvailable = WooAnalyticsEvent.LocalNotification.Key.isIAPAvailable
    }
}

extension LocalNotification {
    init(scenario: Scenario,
          stores: StoresManager = ServiceLocator.stores,
          timeZone: TimeZone = .current,
          locale: Locale = .current,
          userInfo: [AnyHashable: Any] = [:]) {
        /// Name to display in notifications
        let name: String = {
            let sessionManager = stores.sessionManager
            guard let name = sessionManager.defaultAccount?.displayName, name.isNotEmpty else {
                return sessionManager.defaultCredentials?.username ?? ""
            }
            return name
        }()

        let title: String
        let body: String
        let actions: CategoryActions? = nil

        switch scenario {
        case .storeCreationComplete:
            title = Localization.StoreCreationComplete.title
            body = String.localizedStringWithFormat(Localization.StoreCreationComplete.body, name)

        case .oneDayAfterStoreCreationNameWithoutFreeTrial(let storeName):
            title = Localization.OneDayAfterStoreCreationNameWithoutFreeTrial.title
            body = String.localizedStringWithFormat(
                Localization.OneDayAfterStoreCreationNameWithoutFreeTrial.body,
                name,
                storeName
            )

        case let .oneDayBeforeFreeTrialExpires(_, expiryDate):
            title = Localization.OneDayBeforeFreeTrialExpires.title
            let dateFormatStyle = Date.FormatStyle(locale: locale, timeZone: timeZone)
                .weekday(.wide)
                .month(.wide)
                .day(.defaultDigits)
            let displayDate = expiryDate.formatted(dateFormatStyle)
            body = String.localizedStringWithFormat(Localization.OneDayBeforeFreeTrialExpires.body, displayDate)

        case .oneDayAfterFreeTrialExpires:
            title = Localization.OneDayAfterFreeTrialExpires.title
            body = String.localizedStringWithFormat(Localization.OneDayAfterFreeTrialExpires.body, name)

        case .sixHoursAfterFreeTrialSubscribed:
            title = Localization.SixHoursAfterFreeTrialSubscribed.title
            body = Localization.SixHoursAfterFreeTrialSubscribed.body

        case .freeTrialSurvey24hAfterFreeTrialSubscribed:
            title = Localization.FreeTrialSurvey24hAfterFreeTrialSubscribed.title
            body = Localization.FreeTrialSurvey24hAfterFreeTrialSubscribed.body

        case .threeDaysAfterStillExploring:
            title = Localization.ThreeDaysAfterStillExploring.title
            body = Localization.ThreeDaysAfterStillExploring.body
        }

        self.init(title: title,
                  body: body,
                  scenario: scenario,
                  actions: actions,
                  userInfo: userInfo)
    }
}

extension LocalNotification {
    enum Localization {
        enum StoreCreationComplete {
            static let title = NSLocalizedString(
                "🎉 Your store is ready!",
                comment: "Title of the local notification about a newly created store"
            )
            static let body = NSLocalizedString(
                "Hi %1$@, Welcome to your 14-day free trial of Woo Express – " +
                "everything you need to start and grow a successful online business, " +
                "all in one place. Ready to explore?",
                comment: "Message on the local notification about a newly created store." +
                "The placeholder is the name of the user."
            )
        }

        enum OneDayAfterStoreCreationNameWithoutFreeTrial {
            static let title = NSLocalizedString(
                "🛍️ Your store is waiting!",
                comment: "Title of the local notification suggesting a trial plan subscription."
            )
            static let body = NSLocalizedString(
                "Hi %1$@, %2$@ is ready for you! Start your 14-day free trial " +
                "of Woo Express right in just one click to start your online business.",
                comment: "Message on the local notification suggesting a trial plan subscription." +
                "The placeholders are the name of the user and the store name."
            )
        }

        enum OneDayBeforeFreeTrialExpires {
            static let title = NSLocalizedString(
                "⏰ Time’s running out on your free trial!",
                comment: "Title of the local notification to remind the user of expiring free trial plan."
            )
            static let body = NSLocalizedString(
                "Your free trial of Woo Express ends tomorrow (%1$@). Now’s the time to own your future – pick a plan and get ready to grow.",
                comment: "Message on the local notification to remind the user of the expiring free trial plan." +
                "The placeholder is the expiry date of the trial plan."
            )
        }

        enum OneDayAfterFreeTrialExpires {
            static let title = NSLocalizedString(
                "🌟 Keep your business going with our plan!",
                comment: "Title of the local notification to remind the user of the expired free trial plan."
            )
            static let body = NSLocalizedString(
                "%1$@, we have paused your store, but you can continue by picking a plan that suits you best.",
                comment: "Message on the local notification to remind the user of the expired free trial plan." +
                "The placeholder is the name of the user."
            )
        }

        enum SixHoursAfterFreeTrialSubscribed {
            static let title = NSLocalizedString(
                "🌟 Keep your business going!",
                comment: "Title of the local notification to remind the user to purchase a plan."
            )
            static let body = NSLocalizedString(
                "Discover advanced features and personalized recommendations for your store! Tap to pick a plan that suits you best.",
                comment: "Message on the local notification to remind the user to purchase a plan."
            )
        }

        enum FreeTrialSurvey24hAfterFreeTrialSubscribed {
            static let title = NSLocalizedString(
                "💡Help Us Understand Your Subscription Decision",
                comment: "Title of the local notification to ask for Free trial survey."
            )
            static let body = NSLocalizedString(
                "We’re interested in your decision-making journey. Could you please tell us about your current status?",
                comment: "Message on the local notification to ask for Free trial survey."
            )
        }

        enum ThreeDaysAfterStillExploring {
            static let title = NSLocalizedString(
                "🧭 Still Exploring WooCommerce?",
                comment: "Title of the local notification to remind after three days."
            )
            static let body = NSLocalizedString(
                "No rush, take your time! If you have any questions or need assistance, we're always here to help. Happy exploring!",
                comment: "Message on the local notification to remind after three days."
            )
        }
    }
}
