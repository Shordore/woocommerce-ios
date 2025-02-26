import Foundation
import WooFoundation
import UIKit
import Yosemite
import Combine

final class JustInTimeMessageViewModel {
    private let siteID: Int64

    private let analytics: Analytics

    private let stores: StoresManager

    private lazy var urlRouter: UniversalLinkRouter = {
        return UniversalLinkRouter.justInTimeMessagesUniversalLinkRouter(
            tabBarController: AppDelegate.shared.tabBarController,
            urlOpener: JustInTimeMessagesURLOpener(navigationTitle: justInTimeMessage.title,
                                                   showWebViewSheetSubject: showWebViewSheetSubject))
    }()

    private let justInTimeMessage: JustInTimeMessage

    // MARK: - Message properties
    let template: JustInTimeMessageTemplate

    let title: String

    let message: String

    let buttonTitle: String?

    let imageUrl: URL?

    let imageDarkUrl: URL?

    let badgeType: BadgeView.BadgeType?

    private let url: URL?

    private let messageID: String

    private let featureClass: String

    private let screenName: String

    private var cancellables: Set<AnyCancellable> = []

    init(justInTimeMessage: JustInTimeMessage,
         screenName: String,
         siteID: Int64,
         stores: StoresManager = ServiceLocator.stores,
         analytics: Analytics = ServiceLocator.analytics) {
        self.siteID = siteID
        self.analytics = analytics
        self.stores = stores
        let utmProvider = WooCommerceComUTMProvider(
            campaign: "jitm_group_\(justInTimeMessage.featureClass)",
            source: screenName,
            content: "jitm_\(justInTimeMessage.messageID)",
            siteID: siteID)
        self.url = utmProvider.urlWithUtmParams(string: justInTimeMessage.url)
        self.messageID = justInTimeMessage.messageID
        self.featureClass = justInTimeMessage.featureClass
        self.justInTimeMessage = justInTimeMessage
        self.screenName = screenName
        self.template = justInTimeMessage.template
        self.title = justInTimeMessage.title
        self.message = justInTimeMessage.detail
        self.buttonTitle = justInTimeMessage.buttonTitle
        self.imageUrl = justInTimeMessage.backgroundImageUrl
        self.imageDarkUrl = justInTimeMessage.backgroundImageDarkUrl
        if let badgeImageUrl = justInTimeMessage.badgeImageUrl {
            self.badgeType = BadgeView.BadgeType.remoteImage(lightUrl: badgeImageUrl,
                                                             darkUrl: justInTimeMessage.badgeImageDarkUrl)
        } else {
            self.badgeType = nil
        }
        bindWebViewSheet()
    }

    // MARK: - output streams
    @Published var showWebViewSheet: WebViewSheetViewModel?
    private let showWebViewSheetSubject = PassthroughSubject<WebViewSheetViewModel?, Never>()

    private func bindWebViewSheet() {
        showWebViewSheetSubject.sink { [weak self] webViewSheetViewModel in
            self?.showWebViewSheet = webViewSheetViewModel
        }.store(in: &cancellables)
    }

    // MARK: - Actions
    func ctaTapped() {
        trackCtaTapped()
        guard let url = url else {
            return
        }

        urlRouter.handle(url: url)
    }

    func dismissTapped() {
        trackDismissTapped()
        let action = JustInTimeMessageAction.dismissMessage(justInTimeMessage,
                                                            siteID: siteID,
                                                            completion: { result in
            // We deliberately strongly capture self here: the owning reference to the VM may have been
            // set to nil by now, in order to stop displaying the Just In Time Message.
            // [weak self] will result in these two analytics never being logged.
            switch result {
            case .success:
                self.analytics.track(event: .JustInTimeMessage.dismissSuccess(
                    source: self.screenName,
                    messageID: self.messageID,
                    featureClass: self.featureClass))
            case .failure(let error):
                self.analytics.track(event: .JustInTimeMessage.dismissFailure(
                    source: self.screenName,
                    messageID: self.messageID,
                    featureClass: self.featureClass,
                    error: error))
            }
        })
        stores.dispatch(action)
    }

    // MARK: - Analytics
    private func trackMessageDisplayed() {
        analytics.track(event: .JustInTimeMessage.messageDisplayed(source: screenName,
                                                                   messageID: messageID,
                                                                   featureClass: featureClass))
    }

    private func trackCtaTapped() {
        analytics.track(event: .JustInTimeMessage.callToActionTapped(source: screenName,
                                                                     messageID: messageID,
                                                                     featureClass: featureClass))
    }

    private func trackDismissTapped() {
        analytics.track(event: .JustInTimeMessage.dismissTapped(source: screenName,
                                                                messageID: messageID,
                                                                featureClass: featureClass))
    }
}


extension JustInTimeMessageViewModel: AnnouncementCardViewModelProtocol {
    // MARK: - default AnnouncementCardViewModelProtocol conformance
    var showDividers: Bool { false }

    var image: UIImage { .paymentsFeatureBannerImage }

    var showDismissConfirmation: Bool { false }

    var dismissAlertTitle: String {
        switch template {
        case .modal:
            return Localization.maybeLaterButton
        default:
            return ""
        }
    }

    var dismissAlertMessage: String { "" }

    // MARK: - AnnouncementCardViewModelProtocol methods
    func onAppear() {
        trackMessageDisplayed()
    }

    func dontShowAgainTapped() {
        dismissTapped()
    }

    func remindLaterTapped() {
        // No-op
    }
}

private extension JustInTimeMessageViewModel {
    enum Localization {
        static let maybeLaterButton = NSLocalizedString(
            "Maybe Later",
            comment: "Dismiss button title for modally presented Just in Time Messages"
        )
    }
}
