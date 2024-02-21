import Foundation
import Combine
import Networking
import Yosemite

final class ConnectivityToolViewModel {

    /// Cards to be rendered by the view.
    ///
    @Published var cards: [ConnectivityTool.Card] = []

    /// Remote used to check the connection to WPCom servers.
    ///
    private let announcementsRemote: AnnouncementsRemote

    /// Remote used to check the connection to the site.
    ///
    private let systemStatusRemote: SystemStatusRemote

    /// Remote used to check the site orders.
    ///
    private let orderRemote: OrdersRemote?

    /// Site to be tested.
    ///
    private let siteID: Int64

    /// Combine subscriptions.
    ///
    private var subscriptions: Set<AnyCancellable> = []

    init(session: SessionManagerProtocol = ServiceLocator.stores.sessionManager) {

        let network = AlamofireNetwork(credentials: session.defaultCredentials)
        self.announcementsRemote = AnnouncementsRemote(network: network)
        self.systemStatusRemote = SystemStatusRemote(network: network)
        self.orderRemote = OrdersRemote(network: network)
        self.siteID = session.defaultStoreID ?? .zero

        Task {
            await startConnectivityTest()
        }
    }

    /// Sequentially runs all connectivity tests defined in `ConnectivityTest`.
    ///
    private func startConnectivityTest() async {

        for (index, testCase) in ConnectivityTest.allCases.enumerated() {

            // Add an inProgress card for the current test.
            cards.append(testCase.inProgressCard)

            // Run the test.
            let testResult = await runTest(for: testCase)

            // Update the test card with the test result.
            cards[index] = cards[index].updatingState(testResult)

            // Only continue with another test if the current test was successful.
            if case .error = testResult {
                return // Exit connectivity test.
            }
        }
    }

    /// Perform the test for a provided test case.
    ///
    private func runTest(for connectivityTest: ConnectivityTest) async -> ConnectivityToolCard.State {
        switch connectivityTest {
        case .internetConnection:
            return await testInternetConnectivity()
        case .wpComServers:
            return await testWPComServersConnectivity()
        case .site:
            return await testSiteConnectivity()
        case .siteOrders:
            return await testFetchingOrders()

        }
    }

    /// Perform internet connectivity case using the `connectivityObserver`.
    ///
    private func testInternetConnectivity() async -> ConnectivityToolCard.State {
        await withCheckedContinuation { continuation in
            ServiceLocator.connectivityObserver.statusPublisher.first()
                .sink { [weak self] status in
                    guard let self else { return }

                    let reachable = {
                        if case .reachable = status {
                            return true
                        } else {
                            return false
                        }
                    }()

                    let state: ConnectivityToolCard.State = reachable ? .success : .error("No internet connection")
                    continuation.resume(returning: state)
                }
                .store(in: &subscriptions)
        }
    }

    /// Test WPCom connectivity by fetching the mobile announcements.
    ///
    func testWPComServersConnectivity() async -> ConnectivityToolCard.State {
        await withCheckedContinuation { continuation in
            announcementsRemote.loadAnnouncements(appVersion: UserAgent.bundleShortVersion, locale: Locale.current.identifier) { result in
                let state: ConnectivityToolCard.State = result.isSuccess ? .success : .error("Can't reach WordPress.com servers")
                continuation.resume(returning: state)
            }
        }
    }

    /// Test Site connectivity by fetching the status report..
    ///
    func testSiteConnectivity() async -> ConnectivityToolCard.State {
        await withCheckedContinuation { continuation in
            systemStatusRemote.fetchSystemStatusReport(for: siteID) { result in
                let state: ConnectivityToolCard.State = result.isSuccess ? .success : .error("Can't reach your site servers")
                continuation.resume(returning: state)
            }
        }
    }

    /// Test fetching the site orders by actually fetching orders.
    ///
    func testFetchingOrders() async -> ConnectivityToolCard.State {
        await withCheckedContinuation { continuation in
            orderRemote?.loadAllOrders(for: siteID) { result in
                let state: ConnectivityToolCard.State = result.isSuccess ? .success : .error("Can't reach your site servers")
                continuation.resume(returning: state)
            }
        }
    }
}

private extension ConnectivityToolViewModel {
    enum ConnectivityTest: CaseIterable {
        case internetConnection
        case wpComServers
        case site
        case siteOrders

        var title: String {
            switch self {
            case .internetConnection:
                NSLocalizedString("Internet Connection", comment: "Title for the internet connection connectivity tool card")
            case .wpComServers:
                NSLocalizedString("Connecting to WordPress.com Servers", comment: "Title for the WPCom servers connectivity tool card")
            case .site:
                NSLocalizedString("Connecting to your site", comment: "Title for the Your Site connectivity tool card")
            case .siteOrders:
                NSLocalizedString("Fetching your site orders", comment: "Title for the Your Site Orders connectivity tool card")
            }
        }

        var icon: ConnectivityToolCard.Icon {
            switch self {
            case .internetConnection:
                    .system("wifi")
            case .wpComServers:
                    .system("server.rack")
            case .site:
                    .system("storefront")
            case .siteOrders:
                    .system("list.clipboard")
            }
        }

        var inProgressCard: ConnectivityTool.Card {
            .init(title: title, icon: icon, state: .inProgress)
        }
    }
}

extension ConnectivityTool.Card {
    /// Updates a card state to a new given state.
    ///
    func updatingState(_ newState: ConnectivityToolCard.State) -> ConnectivityTool.Card {
        Self.init(title: title, icon: icon, state: newState)
    }
}
