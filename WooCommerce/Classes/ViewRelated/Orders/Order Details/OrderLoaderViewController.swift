import Foundation
import SwiftUI
import UIKit
import Yosemite


// Loads and render an Order details asynchronously.
// This is useful for showing the details of an order coming from a push notification or universal link.
// On Success the OrderDetailsViewController will be rendered "in place".
//
class OrderLoaderViewController: UIViewController {

    /// UI Spinner
    ///
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    /// Source push notification `Note`
    ///
    private let note: Note?

    /// Target OrderID
    ///
    let orderID: Int64

    /// Target Order's SiteID
    ///
    private let siteID: Int64

    /// UI Active State
    ///
    private var state: State = .loading {
        didSet {
            didLeave(state: oldValue)
            didEnter(state: state)
        }
    }

    /// ResultsController: Handles all things order status
    ///
    private lazy var statusResultsController: ResultsController<StorageOrderStatus> = {
        let storageManager = ServiceLocator.storageManager
        let predicate = NSPredicate(format: "siteID == %lld", siteID)
        let descriptor = NSSortDescriptor(key: "slug", ascending: true)
        return ResultsController<StorageOrderStatus>(storageManager: storageManager, matching: predicate, sortedBy: [descriptor])
    }()

    /// ResultsController: Queries for the current order.
    ///
    private lazy var orderResultsController: ResultsController<StorageOrder> = {
        let storageManager = ServiceLocator.storageManager
        let predicate = NSPredicate(format: "siteID == %lld AND orderID == %lld", siteID, orderID)
        return ResultsController<StorageOrder>(storageManager: storageManager, matching: predicate, sortedBy: [])
    }()

    /// The current list of order statuses for the default site
    ///
    private var currentSiteStatuses: [OrderStatus] {
        return statusResultsController.fetchedObjects
    }

    // MARK: - Initializers

    init(orderID: Int64, siteID: Int64, note: Note? = nil) {
        self.orderID = orderID
        self.siteID = siteID
        self.note = note

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Please specify the OrderID and SiteID!")
    }


    // MARK: - Overridden Methods

    override func viewDidLoad() {
        super.viewDidLoad()

        configureResultsController()
        configureNavigationItem()
        configureSpinner()
        configureMainView()

        reloadOrder()
    }
}


// MARK: - Actions
//
private extension OrderLoaderViewController {

    /// Loads (and displays) the specified Order.
    ///
    func reloadOrder() {
        // If we have an stored order there is no point on re-loading it now and delaying the user interface.
        // In any the OrderDetailViewController will reload the order data.
        if let storedOrder = orderResultsController.fetchedObjects.first {
            return self.state = .success(order: storedOrder)
        }

        let action = OrderAction.retrieveOrder(siteID: siteID, orderID: orderID) { [weak self] (order, error) in
            guard let self = self else {
                return
            }

            guard let order = order else {
                DDLogError("## Error loading Order \(self.siteID).\(self.orderID): \(error.debugDescription)")
                self.state = .failure
                return
            }

            self.state = .success(order: order)
        }

        state = .loading
        ServiceLocator.stores.dispatch(action)
    }
}


// MARK: - Configuration
//
private extension OrderLoaderViewController {

    /// Setup: Results Controller
    ///
    func configureResultsController() {
        // Order status FRC
        do {
            try statusResultsController.performFetch()
            try? orderResultsController.performFetch()
        } catch {
            DDLogError("⛔️ Unable to fetch Order Status for Site \(siteID) and Order \(orderID): \(error)")
        }
    }

    /// Setup: Navigation
    ///
    func configureNavigationItem() {
        title = NSLocalizedString("Loading Order", comment: "Displayed when an Order is being retrieved")
    }

    /// Setup: Main View
    ///
    func configureMainView() {
        view.backgroundColor = .listBackground
        view.addSubview(activityIndicator)
        view.pinSubviewAtCenter(activityIndicator)
    }

    /// Setup: Spinner
    ///
    func configureSpinner() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
    }
}


// MARK: - Overlays
//
private extension OrderLoaderViewController {

    /// Starts the Spinner
    ///
    func startSpinner() {
        activityIndicator.startAnimating()
    }

    /// Stops the Spinner
    ///
    func stopSpinner() {
        activityIndicator.stopAnimating()
    }

    /// Displays the Loading Overlay.
    ///
    func displayFailureOverlay() {
        let overlayView: OverlayMessageView = OverlayMessageView.instantiateFromNib()
        overlayView.messageImage = .waitingForCustomersImage
        overlayView.messageText = NSLocalizedString("The Order couldn't be loaded!", comment: "Fetching an Order Failed")
        overlayView.actionText = NSLocalizedString("Retry", comment: "Retry the last action")
        overlayView.onAction = { [weak self] in
            self?.reloadOrder()
        }

        overlayView.attach(to: view)
    }

    /// Removes all of the the OverlayMessageView instances in the view hierarchy.
    ///
    func removeAllOverlays() {
        for subview in view.subviews where subview is OverlayMessageView {
            subview.removeFromSuperview()
        }
    }

    /// Presents the OrderDetailsViewController, as a childViewController, for a given Order.
    ///
    func presentOrderDetails(for order: Order) {
        let viewModel = OrderDetailsViewModel(order: order)
        let detailsViewController = OrderDetailsViewController(viewModel: viewModel)

        // Attach
        addChild(detailsViewController)
        attachSubview(detailsViewController.view)
        detailsViewController.didMove(toParent: self)

        // And, of course, borrow the Child's Title
        title = detailsViewController.title
    }

    /// Removes all of the children UIViewControllers
    ///
    func detachChildrenViewControllers() {
        for child in children {
            child.view.removeFromSuperview()
            child.removeFromParent()
            child.didMove(toParent: nil)
        }
    }
}


// MARK: - UI Methods
//
private extension OrderLoaderViewController {

    /// Attaches a given Subview, and ensures it's pinned to all the edges
    ///
    func attachSubview(_ subview: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subview)
        view.pinSubviewToAllEdges(subview)
    }
}


// MARK: - Private Helpers
//
private extension OrderLoaderViewController {

    func lookUpOrderStatus(for statusKey: String) -> OrderStatus? {
        for orderStatus in currentSiteStatuses where orderStatus.slug == statusKey {
            return orderStatus
        }

        return nil
    }
}


// MARK: - Notification handling
//
private extension OrderLoaderViewController {
    /// Marks a specific Notification as read.
    ///
    func markNotificationAsReadIfNeeded(note: Note) {
        guard note.read == false else {
            return
        }

        let action = NotificationAction.updateReadStatus(noteID: note.noteID, read: true) { (error) in
            if let error = error {
                DDLogError("⛔️ Error marking single notification as read: \(error)")
            }
        }
        ServiceLocator.stores.dispatch(action)
    }
}


// MARK: - Finite State Machine Management
//
private extension OrderLoaderViewController {

    /// Runs whenever the FSM enters a State.
    ///
    func didEnter(state: State) {
        switch state {
        case .loading:
            startSpinner()
        case .success(let order):
            presentOrderDetails(for: order)
            if let note = note {
                markNotificationAsReadIfNeeded(note: note)
            }
        case .failure:
            displayFailureOverlay()
        }
    }

    /// Runs whenever the FSM leaves a State.
    ///
    func didLeave(state: State) {
        switch state {
        case .loading:
            stopSpinner()
        case .success:
            detachChildrenViewControllers()
        case .failure:
            removeAllOverlays()
        }
    }
}


// MARK: - OrderLoader Possible Status(es)
//
private enum State {
    case loading
    case success(order: Order)
    case failure
}

// MARK: - SwiftUI Compatibility
//
struct OrderLoaderView: UIViewControllerRepresentable {
    typealias UIViewControllerType = OrderLoaderViewController
    let orderID: Int64
    let siteID: Int64

    func makeUIViewController(context: Context) -> OrderLoaderViewController {
        OrderLoaderViewController(orderID: orderID,
                                  siteID: siteID)
    }

    func updateUIViewController(_ uiViewController: OrderLoaderViewController, context: Context) {}
}
