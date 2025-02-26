import Foundation
import Yosemite
import Combine
import UIKit
import WooFoundation
import Experiments

import protocol Storage.StorageManagerType

/// ViewModel for the `PaymentsMethodsView`
///
final class PaymentMethodsViewModel: ObservableObject {

    /// Navigation bar title.
    ///
    let title: String

    /// Defines if the view should show a card payment method.
    ///
    @Published private(set) var showPayWithCardRow = false

    @Published private(set) var showTapToPayRow = false

    /// Allows the onboarding flow to be presented before a card present payment when required
    ///
    private let cardPresentPaymentsOnboardingPresenter: CardPresentPaymentsOnboardingPresenting

    /// Defines if the view should show a loading indicator.
    /// Currently set while marking the order as complete
    ///
    @Published private(set) var showLoadingIndicator = false

    /// Stores the payment link for the order.
    ///
    let paymentLink: URL?

    /// Defines if the view should be disabled to prevent any further action.
    /// Useful to prevent any double tap while a network operation is being performed.
    ///
    var disableViewActions: Bool {
        showLoadingIndicator
    }

    /// Defines if the view should show a payment link payment method.
    ///
    var showPaymentLinkRow: Bool {
        paymentLink != nil
    }

    var showScanToPayRow: Bool {
        paymentLink != nil
    }

    /// Store's ID.
    ///
    private let siteID: Int64

    /// Order's ID to update
    ///
    private let orderID: Int64

    /// Formatted total to charge.
    ///
    let formattedTotal: String

    /// Transmits notice presentation intents.
    ///
    private let presentNoticeSubject: PassthroughSubject<PaymentMethodsNotice, Never>

    var notice: AnyPublisher<PaymentMethodsNotice, Never> {
        presentNoticeSubject.eraseToAnyPublisher()
    }

    /// Store manager to update order.
    ///
    private let stores: StoresManager

    /// Storage manager to fetch the order.
    ///
    private let storage: StorageManagerType

    /// Tracks analytics events.
    ///
    private let analytics: Analytics

    /// Defines the flow to be reported in Analytics
    ///
    private let flow: WooAnalyticsEvent.PaymentsFlow.Flow

    private let orderDurationRecorder: OrderDurationRecorderProtocol

    private let featureFlagService: FeatureFlagService

    private let currencySettings: CurrencySettings

    /// Stored orders.
    /// We need to fetch this from our storage layer because we are only provide IDs as dependencies
    /// To keep previews/UIs decoupled from our business logic.
    ///
    private lazy var ordersResultController: ResultsController<StorageOrder> = {
        let predicate = NSPredicate(format: "siteID = %ld AND orderID = %ld", siteID, orderID)
        let controller = ResultsController<StorageOrder>(storageManager: storage, matching: predicate, sortedBy: [])
        try? controller.performFetch()
        return controller
    }()

    /// Retains the use-case so it can perform all of its async tasks.
    ///
    private var collectPaymentsUseCase: CollectOrderPaymentProtocol?

    private let cardPresentPaymentsConfiguration: CardPresentPaymentsConfiguration

    struct Dependencies {
        let presentNoticeSubject: PassthroughSubject<PaymentMethodsNotice, Never>
        let cardPresentPaymentsOnboardingPresenter: CardPresentPaymentsOnboardingPresenting
        let stores: StoresManager
        let storage: StorageManagerType
        let analytics: Analytics
        let cardPresentPaymentsConfiguration: CardPresentPaymentsConfiguration
        let orderDurationRecorder: OrderDurationRecorderProtocol
        let featureFlagService: FeatureFlagService
        let currencySettings: CurrencySettings

        init(presentNoticeSubject: PassthroughSubject<PaymentMethodsNotice, Never> = PassthroughSubject(),
             cardPresentPaymentsOnboardingPresenter: CardPresentPaymentsOnboardingPresenting = CardPresentPaymentsOnboardingPresenter(),
             stores: StoresManager = ServiceLocator.stores,
             storage: StorageManagerType = ServiceLocator.storageManager,
             analytics: Analytics = ServiceLocator.analytics,
             cardPresentPaymentsConfiguration: CardPresentPaymentsConfiguration? = nil,
             orderDurationRecorder: OrderDurationRecorderProtocol = OrderDurationRecorder.shared,
             featureFlagService: FeatureFlagService = ServiceLocator.featureFlagService,
             currencySettings: CurrencySettings = ServiceLocator.currencySettings) {
            self.presentNoticeSubject = presentNoticeSubject
            self.cardPresentPaymentsOnboardingPresenter = cardPresentPaymentsOnboardingPresenter
            self.stores = stores
            self.storage = storage
            self.analytics = analytics
            let configuration = cardPresentPaymentsConfiguration ?? CardPresentConfigurationLoader(stores: stores).configuration
            self.cardPresentPaymentsConfiguration = configuration
            self.orderDurationRecorder = orderDurationRecorder
            self.featureFlagService = featureFlagService
            self.currencySettings = currencySettings
        }
    }

    init(siteID: Int64 = 0,
         orderID: Int64 = 0,
         paymentLink: URL? = nil,
         formattedTotal: String,
         flow: WooAnalyticsEvent.PaymentsFlow.Flow,
         dependencies: Dependencies = Dependencies()) {
        self.siteID = siteID
        self.orderID = orderID
        self.paymentLink = paymentLink
        self.formattedTotal = formattedTotal
        self.flow = flow
        self.orderDurationRecorder = dependencies.orderDurationRecorder
        presentNoticeSubject = dependencies.presentNoticeSubject
        cardPresentPaymentsOnboardingPresenter = dependencies.cardPresentPaymentsOnboardingPresenter
        stores = dependencies.stores
        storage = dependencies.storage
        analytics = dependencies.analytics
        cardPresentPaymentsConfiguration = dependencies.cardPresentPaymentsConfiguration
        featureFlagService = dependencies.featureFlagService
        currencySettings = dependencies.currencySettings
        title = String(format: Localization.title, formattedTotal)

        bindStoreCPPState()
        updateCardPaymentVisibility()
        logOrderAndStoreCurrencyMismatch()
    }

    @MainActor
    func markOrderAsPaidByCash(with info: OrderPaidByCashInfo?) async {
        showLoadingIndicator = true
        do {
            try await markOrderCompletedWithCashOnDelivery()
            updateOrderAsynchronously()
            if let info, info.addNoteWithChangeData {
                await addPaidByCashNoteToOrder(with: info)
            }
            finishOrderPaidByCashFlow()
        } catch {
            presentNoticeSubject.send(.error(Localization.markAsPaidError))
            trackFlowFailed()
        }
    }

    /// Starts the collect payment flow in the provided `rootViewController`
    /// - parameter useCase: Assign a custom useCase object for testing purposes. If not provided `CollectOrderPaymentUseCase` will be used.
    ///
    func collectPayment(using discoveryMethod: CardReaderDiscoveryMethod,
                        on rootViewController: UIViewController?,
                        useCase: CollectOrderPaymentProtocol? = nil,
                        onSuccess: @escaping () -> Void,
                        onFailure: @escaping () -> Void) {
        trackCollectIntention(method: .card, cardReaderType: discoveryMethod.analyticsCardReaderType)
        orderDurationRecorder.recordCardPaymentStarted()

        guard let rootViewController = rootViewController else {
            DDLogError("⛔️ Root ViewController is nil, can't present payment alerts.")
            return presentNoticeSubject.send(.error(Localization.genericCollectError))
        }

        guard let order = ordersResultController.fetchedObjects.first else {
            DDLogError("⛔️ Order not found, can't collect payment.")
            return presentNoticeSubject.send(.error(Localization.genericCollectError))
        }
        let alertsPresenter = CardPresentPaymentAlertsPresenter(rootViewController: rootViewController)
        let analyticsTracker = CardReaderConnectionAnalyticsTracker(
            configuration: cardPresentPaymentsConfiguration,
            siteID: siteID,
            connectionType: .userInitiated,
            stores: stores,
            analytics: analytics)
        let externalReaderConnectionController = CardReaderConnectionController(
            forSiteID: siteID,
            knownReaderProvider: CardReaderSettingsKnownReaderStorage(),
            alertsPresenter: alertsPresenter,
            alertsProvider: BluetoothReaderConnectionAlertsProvider(),
            configuration: cardPresentPaymentsConfiguration,
            analyticsTracker: analyticsTracker)
        let tapToPayAlertsProvider = BuiltInReaderConnectionAlertsProvider()
        let tapToPayConnectionController = BuiltInCardReaderConnectionController(
            forSiteID: siteID,
            alertsPresenter: alertsPresenter,
            alertsProvider: tapToPayAlertsProvider,
            configuration: cardPresentPaymentsConfiguration,
            analyticsTracker: analyticsTracker)

        collectPaymentsUseCase = useCase ?? CollectOrderPaymentUseCase<BuiltInCardReaderPaymentAlertsProvider,
                                                                        BluetoothCardReaderPaymentAlertsProvider,
                                                                        CardPresentPaymentAlertsPresenter>(
            siteID: self.siteID,
            order: order,
            formattedAmount: self.formattedTotal,
            rootViewController: rootViewController,
            configuration: cardPresentPaymentsConfiguration,
            alertsPresenter: alertsPresenter,
            tapToPayAlertsProvider: BuiltInCardReaderPaymentAlertsProvider(),
            bluetoothAlertsProvider: BluetoothCardReaderPaymentAlertsProvider(transactionType: .collectPayment),
            preflightController: CardPresentPaymentPreflightController(siteID: siteID,
                                                                       configuration: cardPresentPaymentsConfiguration,
                                                                       rootViewController: rootViewController,
                                                                       alertsPresenter: alertsPresenter,
                                                                       onboardingPresenter: self.cardPresentPaymentsOnboardingPresenter,
                                                                       tapToPayAlertProvider: tapToPayAlertsProvider,
                                                                       externalReaderConnectionController: externalReaderConnectionController,
                                                                       tapToPayConnectionController: tapToPayConnectionController,
                                                                       tapToPayReconnectionController: ServiceLocator.tapToPayReconnectionController,
                                                                       analyticsTracker: analyticsTracker))

        collectPaymentsUseCase?.collectPayment(
            using: discoveryMethod,
            onFailure: { [weak self] error in
                self?.trackFlowFailed()
                // Update order in case its status and/or other details are updated after a failed in-person payment
                self?.updateOrderAsynchronously()

                onFailure()
            },
            onCancel: {
                // No tracking required because the flow remains on screen to choose other payment methods.
            },
            onPaymentCompletion: {
                // No tracking required at present because it's handled internally.
            },
            onCompleted: { [weak self] in
                // Update order in case its status and/or other details are updated after a successful in-person payment
                self?.updateOrderAsynchronously()

                // Inform success to consumer
                onSuccess()

                // Sent notice request
                self?.presentNoticeSubject.send(.completed)

                // Make sure we free all the resources
                self?.collectPaymentsUseCase = nil

                // Tracks completion
                self?.trackFlowCompleted(method: .card, cardReaderType: discoveryMethod.analyticsCardReaderType)
            })
    }

    /// Tracks the collect by cash intention.
    ///
    func trackCollectByCash() {
        trackCollectIntention(method: .cash, cardReaderType: .none)
    }

    func trackCollectByPaymentLink() {
        trackCollectIntention(method: .paymentLink, cardReaderType: .none)
    }

    func trackCollectByScanToPay() {
        trackCollectIntention(method: .scanToPay, cardReaderType: .none)
    }

    /// Perform the necesary tasks after a link is shared.
    ///
    func performLinkSharedTasks() {
        presentNoticeSubject.send(.created)
        trackFlowCompleted(method: .paymentLink, cardReaderType: .none)
    }

    func performScanToPayFinishedTasks() {
        presentNoticeSubject.send(.created)
        trackFlowCompleted(method: .scanToPay, cardReaderType: .none)
    }

    /// Track the flow cancel scenario.
    ///
    func userDidCancelFlow() {
        trackFlowCanceled()
    }

    /// Logs an error when `PaymentMethodsView.rootViewController` is missing.
    func logNoRootViewControllerError() {
        let logProperties: [String: Any] = ["flow": flow.rawValue]
        ServiceLocator.crashLogging.logMessage(
            "Missing `rootViewController` in `PaymentMethodsView` can result in a broken IPP experience",
            properties: logProperties,
            level: .error
        )
        assertionFailure("Missing `rootViewController` in `PaymentMethodsView` can result in a broken IPP experience in flow: \(flow.rawValue)")
    }

    /// Defines if the swipe-to-dismiss gesture on the payment flow should be enabled
    ///
    var shouldEnableSwipeToDismiss: Bool {
        true
    }
}

// MARK: - Cash Payment

private extension PaymentMethodsViewModel {
    /// Mark an order as Completed with Cash on Delivery payment method
    ///
    @MainActor
    func markOrderCompletedWithCashOnDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let order = ordersResultController.fetchedObjects.first else {
                DDLogError("⛔️ Order \(orderID) not found, can't mark order as paid.")
                continuation.resume(throwing: PaymentMethodsError.orderNotFound)
                return
            }

            let cashOnDeliveryID = PaymentGateway.Constants.cashOnDeliveryGatewayID
            let cashOnDeliveryPaymentGateway = storage.viewStorage.loadPaymentGateway(siteID: siteID, gatewayID: cashOnDeliveryID)
            let cashOnDeliveryTitle = cashOnDeliveryPaymentGateway?.title ?? Localization.cashOnDeliveryPaymentMethodTitle

            let modifiedOrder = order.copy(status: .completed,
                                           paymentMethodID: cashOnDeliveryID,
                                           paymentMethodTitle: cashOnDeliveryTitle)
            let fieldsToUpdate: [OrderUpdateField] = [.status, .paymentMethodID, .paymentMethodTitle]
            stores.dispatch(OrderAction.updateOrder(siteID: siteID,
                                                    order: modifiedOrder,
                                                    giftCard: nil,
                                                    fields: fieldsToUpdate,
                                                    onCompletion: { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }))
        }
    }

    @MainActor
    func addPaidByCashNoteToOrder(with info: OrderPaidByCashInfo) async {
        await withCheckedContinuation { continuation in
            let noteText = String.localizedStringWithFormat(Localization.orderPaidByCashNoteText, info.customerPaidAmount, info.changeGivenAmount)
            stores.dispatch(OrderNoteAction.addOrderNote(siteID: siteID,
                                                      orderID: orderID,
                                                      isCustomerNote: false,
                                                      note: noteText) { _, _ in
                continuation.resume(returning: ())
            })
        }
    }

    func finishOrderPaidByCashFlow() {
        showLoadingIndicator = false
        presentNoticeSubject.send(.completed)
        trackFlowCompleted(method: .cash, cardReaderType: .none)
    }
}

// MARK: - Helpers
private extension PaymentMethodsViewModel {
    /// Observes the store CPP state and update publish variables accordingly.
    ///
    func bindStoreCPPState() {
        ordersResultController.onDidChangeContent = { [weak self] in
            self?.updateCardPaymentVisibility()
        }
        try? ordersResultController.performFetch()
    }

    func updateCardPaymentVisibility() {
        guard cardPresentPaymentsConfiguration.isSupportedCountry else {
            showPayWithCardRow = false
            showTapToPayRow = false

            return
        }

        localMobileReaderSupported { [weak self] tapToPaySupportedByDevice in
            let tapToPaySupportedByStore = self?.cardPresentPaymentsConfiguration.supportedReaders.contains(.appleBuiltIn) ?? false
            self?.orderIsEligibleForCardPresentPayment { [weak self] orderIsEligible in
                self?.showPayWithCardRow = orderIsEligible
                self?.showTapToPayRow = orderIsEligible && tapToPaySupportedByDevice && tapToPaySupportedByStore
            }
        }
    }

    private func localMobileReaderSupported(onCompletion: @escaping ((Bool) -> Void)) {
        let action = CardPresentPaymentAction.checkDeviceSupport(
            siteID: siteID,
            cardReaderType: .appleBuiltIn,
            discoveryMethod: .localMobile,
            minimumOperatingSystemVersionOverride: cardPresentPaymentsConfiguration.minimumOperatingSystemVersionForTapToPay,
            onCompletion: onCompletion)
        stores.dispatch(action)
    }

    private func orderIsEligibleForCardPresentPayment(onCompletion: @escaping (Bool) -> Void) {
        let action = OrderCardPresentPaymentEligibilityAction
            .orderIsEligibleForCardPresentPayment(orderID: orderID,
                                                  siteID: siteID,
                                                  cardPresentPaymentsConfiguration: cardPresentPaymentsConfiguration) { result in
                switch result {
                case .success(let eligibility):
                    onCompletion(eligibility)
                case .failure:
                    onCompletion(false)
                }
            }

        stores.dispatch(action)
    }

    func updateOrderAsynchronously() {
        let action = OrderAction.retrieveOrder(siteID: siteID, orderID: orderID) { _, _  in }
        stores.dispatch(action)
    }

    /// Tracks the `paymentsFlowCompleted` event.
    ///
    func trackFlowCompleted(method: WooAnalyticsEvent.PaymentsFlow.PaymentMethod,
                            cardReaderType: WooAnalyticsEvent.PaymentsFlow.CardReaderType?) {
        let currencyFormatter = CurrencyFormatter(currencySettings: currencySettings)
        let amountNormalized = currencyFormatter.convertToDecimal(formattedTotal) ?? 0

        let amountInSmallestUnit = amountNormalized
            .multiplying(by: NSDecimalNumber(value: currencySettings.currencyCode.smallestCurrencyUnitMultiplier))
            .intValue

        analytics.track(event: WooAnalyticsEvent.PaymentsFlow.paymentsFlowCompleted(flow: flow,
                                                                                    amount: formattedTotal,
                                                                                    amountNormalized: amountInSmallestUnit,
                                                                                    country: cardPresentPaymentsConfiguration.countryCode,
                                                                                    currency: currencySettings.currencyCode.rawValue,
                                                                                    method: method,
                                                                                    orderID: orderID,
                                                                                    cardReaderType: cardReaderType))
    }

    /// Tracks the `paymentsFlowFailed` event.
    ///
    func trackFlowFailed() {
        analytics.track(event: WooAnalyticsEvent.PaymentsFlow.paymentsFlowFailed(flow: flow,
                                                                                 source: .paymentMethod,
                                                                                 country: cardPresentPaymentsConfiguration.countryCode,
                                                                                 currency: currencySettings.currencyCode.rawValue))
    }

    /// Tracks the `paymentsFlowCanceled` event.
    ///
    func trackFlowCanceled() {
        analytics.track(event: WooAnalyticsEvent.PaymentsFlow.paymentsFlowCanceled(flow: flow,
                                                                                   country: cardPresentPaymentsConfiguration.countryCode,
                                                                                   currency: currencySettings.currencyCode.rawValue))
    }

    /// Tracks `paymentsFlowCollect` event.
    ///
    func trackCollectIntention(method: WooAnalyticsEvent.PaymentsFlow.PaymentMethod,
                               cardReaderType: WooAnalyticsEvent.PaymentsFlow.CardReaderType?) {

        analytics.track(event: WooAnalyticsEvent.PaymentsFlow.paymentsFlowCollect(flow: flow,
                                                                                  method: method,
                                                                                  orderID: orderID,
                                                                                  cardReaderType: cardReaderType,
                                                                                  millisecondsSinceOrderAddNew:
                                                                                    try? orderDurationRecorder.millisecondsSinceOrderAddNew(),
                                                                                  country: cardPresentPaymentsConfiguration.countryCode,
                                                                                  currency: currencySettings.currencyCode.rawValue))
    }
}

private extension PaymentMethodsViewModel {
    /// If the store supports multi-currency
    /// and an account has a different default currency set in store's settings
    /// then some payment methods may be unavailable
    ///
    /// Logging this case for easier debugging
    /// #13580
    private func logOrderAndStoreCurrencyMismatch() {
        guard let order = ordersResultController.fetchedObjects.first else {
            return
        }

        if order.currency != currencySettings.currencyCode.rawValue {
            // swiftlint:disable:next line_length
            DDLogWarn("⚠️ Order currency \(order.currency) differs from store's currency \(currencySettings.currencyCode.rawValue) which can lead to payment methods being unavailable")
        }
    }
}

private extension PaymentMethodsViewModel {
    enum Localization {
        static let markAsPaidError = NSLocalizedString("There was an error while marking the order as paid.",
                                                       comment: "Text when there is an error while marking the order as paid for during payment.")

        static let genericCollectError = NSLocalizedString("There was an error while trying to collect the payment.",
                                                       comment: "Text when there is an unknown error while trying to collect payments")

        static let title = NSLocalizedString("Take Payment (%1$@)",
                                             comment: "Navigation bar title for the Payment Methods screens. " +
                                             "%1$@ is a placeholder for the total amount to collect")

        static let orderPaidByCashNoteText = NSLocalizedString("paymentMethods.orderPaidByCashNoteText.note",
                                                               value: "The order was paid by cash. Customer paid %1$@. The change due was %2$@.",
                                                               comment: "Note from the cash tender view.")
        static let cashOnDeliveryPaymentMethodTitle = NSLocalizedString("paymentMethods.cashOnDelivery.title",
                                                                        value: "Pay in Person",
                                                                        comment: "A title for a payment method where customer pays by cash in person")
    }
}

/// Representation of possible notices that can be displayed from the payment methods flow
///
enum PaymentMethodsNotice: Equatable {
    case created
    case completed
    case error(String)
}

enum PaymentMethodsError: Error {
    case orderNotFound
}

private extension CardReaderDiscoveryMethod {
    var analyticsCardReaderType: WooAnalyticsEvent.PaymentsFlow.CardReaderType {
        switch self {
        case .localMobile:
            return .builtIn
        case .bluetoothScan:
            return .external
        }
    }
}
