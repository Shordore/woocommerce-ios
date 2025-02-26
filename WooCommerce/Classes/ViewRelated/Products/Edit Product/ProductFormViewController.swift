import Combine
import SafariServices
import Photos
import UIKit
import WordPressUI
import Yosemite
import protocol Storage.StorageManagerType

/// The entry UI for adding/editing a Product.
final class ProductFormViewController<ViewModel: ProductFormViewModelProtocol>: UIViewController, UITableViewDelegate {
    typealias ProductModel = ViewModel.ProductModel

    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var moreDetailsContainerView: UIView!

    private lazy var keyboardFrameObserver: KeyboardFrameObserver = {
        let keyboardFrameObserver = KeyboardFrameObserver { [weak self] keyboardFrame in
            self?.handleKeyboardFrameUpdate(keyboardFrame: keyboardFrame)
        }
        return keyboardFrameObserver
    }()

    private let viewModel: ViewModel
    private let eventLogger: ProductFormEventLoggerProtocol

    private var product: ProductModel {
        viewModel.productModel
    }

    private var password: String? {
        viewModel.password
    }

    private var productOrVariationID: ProductOrVariationID {
        if let viewModel = viewModel as? ProductVariationFormViewModel {
            return .variation(productID: viewModel.productModel.productID, variationID: viewModel.productModel.productVariation.productVariationID)
        } else {
            return .product(id: viewModel.productModel.productID)
        }
    }

    private var tableViewModel: ProductFormTableViewModel
    private var tableViewDataSource: ProductFormTableViewDataSource {
        didSet {
            registerTableViewCells()
        }
    }

    private let productImageActionHandler: ProductImageActionHandler
    private let productUIImageLoader: ProductUIImageLoader
    private let productImageUploader: ProductImageUploaderProtocol
    private var tooltipPresenter: TooltipPresenter?

    private let currency: String

    private lazy var exitForm: () -> Void = {
        presentationStyle.createExitForm(viewController: self)
    }()

    private lazy var shareBarButtonItem = UIBarButtonItem(title: Localization.share,
                                                          style: .plain,
                                                          target: self,
                                                          action: #selector(shareProduct))

    private let presentationStyle: ProductFormPresentationStyle
    private let navigationRightBarButtonItemsSubject = PassthroughSubject<[UIBarButtonItem], Never>()
    private var navigationRightBarButtonItems: AnyPublisher<[UIBarButtonItem], Never> {
        navigationRightBarButtonItemsSubject.eraseToAnyPublisher()
    }
    private var productSubscription: AnyCancellable?
    private var productNameSubscription: AnyCancellable?
    private var updateEnabledSubscription: AnyCancellable?
    private var newVariationsPriceSubscription: AnyCancellable?
    private var productImageStatusesSubscription: AnyCancellable?
    private var blazeEligibilitySubscription: AnyCancellable?

    private let aiEligibilityChecker: ProductFormAIEligibilityChecker
    private var descriptionAICoordinator: ProductDescriptionAICoordinator?
    private let subscriptionProductsEligibilityChecker: WooSubscriptionProductsEligibilityCheckerProtocol

    private lazy var tooltipUseCase = ProductDescriptionAITooltipUseCase(isDescriptionAIEnabled: aiEligibilityChecker.isFeatureEnabled(.description))
    private var didShowTooltip = false {
        didSet {
            tooltipUseCase.numberOfTimesWriteWithAITooltipIsShown += 1
        }
    }

    /// The coordinator for sharing products
    ///
    private var shareProductCoordinator: ShareProductCoordinator?

    /// Whether the product details were generated with AI.
    ///
    private let isAIContent: Bool

    /// The coordinator for creating Blaze campaign
    ///
    private var blazeCampaignCreationCoordinator: BlazeCampaignCreationCoordinator?

    private let onDeleteCompletion: () -> Void

    private let userDefaults: UserDefaults

    init(viewModel: ViewModel,
         isAIContent: Bool = false,
         eventLogger: ProductFormEventLoggerProtocol,
         productImageActionHandler: ProductImageActionHandler,
         currency: String = ServiceLocator.currencySettings.symbol(from: ServiceLocator.currencySettings.currencyCode),
         storageManager: StorageManagerType = ServiceLocator.storageManager,
         presentationStyle: ProductFormPresentationStyle,
         productImageUploader: ProductImageUploaderProtocol = ServiceLocator.productImageUploader,
         userDefaults: UserDefaults = .standard,
         onDeleteCompletion: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.isAIContent = isAIContent
        self.eventLogger = eventLogger
        self.currency = currency
        self.presentationStyle = presentationStyle
        self.productImageActionHandler = productImageActionHandler
        self.productUIImageLoader = DefaultProductUIImageLoader(productImageActionHandler: productImageActionHandler,
                                                                phAssetImageLoaderProvider: { PHImageManager.default() })
        self.userDefaults = userDefaults
        self.productImageUploader = productImageUploader
        self.onDeleteCompletion = onDeleteCompletion
        self.aiEligibilityChecker = .init(site: ServiceLocator.stores.sessionManager.defaultSite)
        self.subscriptionProductsEligibilityChecker = WooSubscriptionProductsEligibilityChecker(siteID: viewModel.productModel.siteID, storage: storageManager)
        self.tableViewModel = DefaultProductFormTableViewModel(product: viewModel.productModel,
                                                               actionsFactory: viewModel.actionsFactory,
                                                               currency: currency,
                                                               isDescriptionAIEnabled: aiEligibilityChecker.isFeatureEnabled(.description))
        self.tableViewDataSource = ProductFormTableViewDataSource(viewModel: tableViewModel,
                                                                  productImageStatuses: productImageActionHandler.productImageStatuses,
                                                                  productUIImageLoader: productUIImageLoader)

        super.init(nibName: "ProductFormViewController", bundle: nil)
        updateDataSourceActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        productSubscription?.cancel()
        productNameSubscription?.cancel()
        updateEnabledSubscription?.cancel()
        newVariationsPriceSubscription?.cancel()
        blazeEligibilitySubscription?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configurePresentationStyle()
        configureNavigationBar()

        configureMainView()
        configureTableView()
        configureMoreDetailsContainerView()

        startListeningToNotifications()
        handleSwipeBackGesture()

        observeProduct()
        observeProductName()
        observeUpdateCTAVisibility()
        observeVariationsPriceChanges()
        observeUpdateBlazeEligibility()

        productImageStatusesSubscription = productImageActionHandler.addUpdateObserver(self) { [weak self] (productImageStatuses, error) in
            guard let self = self else {
                return
            }

            if error != nil {
                let title = NSLocalizedString("Cannot upload image", comment: "The title of the alert when there is an error uploading an image")
                let message = NSLocalizedString("Please try again.", comment: "The message of the alert when there is an error uploading an image")
                self.displayErrorAlert(title: title, message: message)
            }

            self.onImageStatusesUpdated(statuses: productImageStatuses)

            self.viewModel.updateImages(productImageStatuses.images)
        }

        productImageUploader.stopEmittingErrors(key: .init(siteID: viewModel.productModel.siteID,
                                                           productOrVariationID: productOrVariationID,
                                                           isLocalID: !viewModel.productModel.existsRemotely))

        viewModel.trackProductFormLoaded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        view.endEditing(true)

        if isBeingDismissedInAnyWay {
            productImageUploader.startEmittingErrors(key: .init(siteID: viewModel.productModel.siteID,
                                                                productOrVariationID: productOrVariationID,
                                                                isLocalID: !viewModel.productModel.existsRemotely))
        }
    }

    override var shouldShowOfflineBanner: Bool {
        return true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        updateNavigationBarTitle()
    }

    // MARK: - Navigation actions handling

    override func shouldPopOnBackButton() -> Bool {
        guard viewModel.hasUnsavedChanges() == false else {
            presentBackNavigationActionSheet()
            return false
        }
        return true
    }

    override func shouldPopOnSwipeBack() -> Bool {
        return shouldPopOnBackButton()
    }

    // MARK: Product save action handling

    func dismissOrPopViewController() {
        switch self.presentationStyle {
        case .navigationStack:
            self.navigationController?.popViewController(animated: true)
        default:
            self.dismiss(animated: true, completion: nil)
        }
    }

    @objc func saveProductAndLogEvent() {
        eventLogger.logUpdateButtonTapped()
        saveProduct()
    }

    @objc func publishProduct() {
        if viewModel.formType == .add {
            ServiceLocator.analytics.track(.addProductPublishTapped, withProperties: ["product_type": product.productType.rawValue])
        } else if viewModel.formType == .edit && isAIContent {
            ServiceLocator.analytics.track(.addProductPublishTapped, withProperties: [
                "product_type": product.productType.rawValue,
                "is_ai_content": isAIContent
            ])
        }
        saveProduct(status: .published)
    }

    func saveProductAsDraft() {
        if viewModel.formType == .add {
            ServiceLocator.analytics.track(.addProductSaveAsDraftTapped, withProperties: ["product_type": product.productType.rawValue])
        }
        saveProduct(status: .draft)
    }

    // MARK: Product preview action handling

    @objc private func saveDraftAndDisplayProductPreview() {
        if viewModel.formType == .add {
            ServiceLocator.analytics.track(.addProductSaveAsDraftTapped, withProperties: ["product_type": product.productType.rawValue])
        }

        guard viewModel.canSaveAsDraft() || viewModel.hasUnsavedChanges() else {
            displayProductPreview()
            return
        }

        saveProduct(status: .draft) { [weak self] result in
            if result.isSuccess {
                self?.displayProductPreview()
            }
        }
    }

    private func displayProductPreview() {
        ServiceLocator.analytics.track(event: .ProductDetail.previewTapped())

        guard var permalink = URLComponents(string: product.permalink),
              let nonce = ServiceLocator.stores.sessionManager.defaultSite?.frameNonce else {
            return
        }

        var updatedQueryItems = permalink.queryItems ?? []
        updatedQueryItems.append(.init(name: "preview", value: "true"))
        updatedQueryItems.append(.init(name: "frame-nonce", value: nonce))
        permalink.queryItems = updatedQueryItems

        let configuration = WebViewControllerConfiguration(url: permalink.url)
        configuration.secureInteraction = true
        let webKitVC = WebKitViewController(configuration: configuration)
        let nc = WooNavigationController(rootViewController: webKitVC)
        present(nc, animated: true)
    }

    // MARK: Navigation actions

    /// Closes the product form if the product has no unsaved changes or the user chooses to discard the changes.
    /// - Parameters:
    ///   - completion: Called when the product form is closed.
    ///   - onCancel: Called when the user chooses not to close the form from the confirmation alert.
    func close(completion: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}) {
        guard viewModel.hasUnsavedChanges() == false else {
            presentBackNavigationActionSheet(onDiscard: completion, onCancel: onCancel)
            return
        }
        exitForm()
        completion()
    }

    @objc private func closeNavigationBarButtonTapped() {
        close()
    }

    // MARK: Action Sheet

    /// More Options Action Sheet
    ///
    @objc func presentMoreOptionsActionSheet(_ sender: UIBarButtonItem) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = .text

        if viewModel.canShowPublishOption() {
            actionSheet.addDefaultActionWithTitle(Localization.publishTitle) { [weak self] _ in
                self?.publishProduct()
            }
        }

        if viewModel.canSaveAsDraft() {
            actionSheet.addDefaultActionWithTitle(ActionSheetStrings.saveProductAsDraft) { [weak self] _ in
                self?.saveProductAsDraft()
            }
        }

        /// The "View product in store" action will be shown only if the product is published.
        if viewModel.canViewProductInStore() {
            actionSheet.addDefaultActionWithTitle(ActionSheetStrings.viewProduct) { [weak self] _ in
                ServiceLocator.analytics.track(.productDetailViewProductButtonTapped)
                self?.displayWebViewForProductInStore()
            }
        }

        if viewModel.canShareProduct() {
            actionSheet.addDefaultActionWithTitle(ActionSheetStrings.share) { [weak self] _ in
                self?.displayShareProduct(from: sender, analyticSource: .moreMenu)
            }
        }

        if viewModel.canEditProductSettings() {
            actionSheet.addDefaultActionWithTitle(ActionSheetStrings.productSettings) { [weak self] _ in
                ServiceLocator.analytics.track(.productDetailViewSettingsButtonTapped)
                self?.displayProductSettings()
            }
        }

        if viewModel.canDuplicateProduct() {
            actionSheet.addDefaultActionWithTitle(ActionSheetStrings.duplicate) { [weak self] _ in
                ServiceLocator.analytics.track(.productDetailDuplicateButtonTapped)
                self?.duplicateProduct()
            }
        }

        if viewModel.canDeleteProduct() {
            actionSheet.addDestructiveActionWithTitle(ActionSheetStrings.trashProduct) { [weak self] _ in
                self?.displayDeleteProductAlert()
            }
        }

        actionSheet.addCancelActionWithTitle(ActionSheetStrings.cancel) { _ in
        }

        let popoverController = actionSheet.popoverPresentationController
        popoverController?.barButtonItem = sender

        present(actionSheet, animated: true)
    }


    // MARK: - UIScrollViewDelegate
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !didShowTooltip else {
            return
        }

        if let tooltipPresenter,
           isDescriptionAICellVisible() {
            tooltipPresenter.showTooltip()
            didShowTooltip = true
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let section = tableViewModel.sections[indexPath.section]
        switch section {
        case .primaryFields(let rows):
            let row = rows[indexPath.row]
            switch row {
            case .images(_, let isStorePublic, _, _):
                guard isStorePublic else {
                    presentURL(URLs.wpComPrivacySettings)
                    return
                }
            case .description(_, let isEditable, _):
                guard isEditable else {
                    return
                }
                eventLogger.logDescriptionTapped()
                editProductDescription()
            case .promoteWithBlaze:
                if !viewModel.shouldShowBlazeIntroView {
                    ServiceLocator.analytics.track(event: .Blaze.blazeEntryPointTapped(source: .productDetailPromoteButton))
                }
                displayBlaze()
            default:
                break
            }
        case .settings(let rows):
            let row = rows[indexPath.row]
            switch row {
            case .price(_, let isEditable):
                guard isEditable else {
                    return
                }
                eventLogger.logPriceSettingsTapped()
                editPriceSettings()
            case .customFields:
                // TODO-13493: add tap handling.
                return
            case .reviews:
                ServiceLocator.analytics.track(.productDetailViewReviewsTapped)
                showReviews()
            case .downloadableFiles(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewDownloadableFilesTapped)
                showDownloadableFiles()
            case .linkedProducts(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewLinkedProductsTapped)
                editLinkedProducts()
            case .productType(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewProductTypeTapped)
                let cell = tableView.cellForRow(at: indexPath)
                editProductType(cell: cell)
            case .shipping(_, let isEditable):
                guard isEditable else {
                    return
                }
                eventLogger.logShippingSettingsTapped()
                editShippingSettings()
            case .inventory(_, let isEditable):
                guard isEditable else {
                    return
                }
                eventLogger.logInventorySettingsTapped()
                editInventorySettings()
            case .addOns(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(event: .ProductDetailAddOns.productAddOnsButtonTapped(productID: product.productID))
                navigateToAddOns()
            case .categories(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewCategoriesTapped)
                editCategories()
            case .tags(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewTagsTapped)
                editTags()
            case .shortDescription(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewShortDescriptionTapped)
                editShortDescription()
            case .externalURL(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewExternalProductLinkTapped)
                editExternalLink()
                break
            case .sku(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewSKUTapped)
                editSKU()
                break
            case .groupedProducts(_, let isEditable):
                guard isEditable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewGroupedProductsTapped)
                editGroupedProducts()
                break
            case .variations(let row):
                guard row.isActionable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewVariationsTapped)
                showVariations()
            case .noPriceWarning(let viewModel):
                guard viewModel.isActionable else {
                    return
                }
                ServiceLocator.analytics.track(.productDetailViewVariationsTapped)
                showVariations()
            case .attributes(_, let isEditable):
                guard isEditable else {
                    return
                }
                editAttributes()
            case .status:
                break
            case .bundledProducts(_, let isActionable):
                guard isActionable else {
                    return
                }
                ServiceLocator.analytics.track(event: .ProductDetail.bundledProductsTapped())
                showBundledProducts()
            case .components(_, let isActionable):
                guard isActionable else {
                    return
                }
                ServiceLocator.analytics.track(event: .ProductDetail.componentsTapped())
                showCompositeComponents()
            case .subscriptionFreeTrial(_, let isEditable):
                guard isEditable else {
                    return
                }

                eventLogger.logSubscriptionsFreeTrialTapped()
                showSubscriptionFreeTrialSettings()
            case .subscriptionExpiry(_, let isEditable):
                guard isEditable else {
                    return
                }

                eventLogger.logSubscriptionsExpirationDateTapped()
                showSubscriptionExpirySettings()
            case .noVariationsWarning:
                return // This warning is not actionable.
            case .quantityRules:
                eventLogger.logQuantityRulesTapped()
                showQuantityRules()
                return
            }
        }
    }

    @objc private func shareProduct() {
        displayShareProduct(from: shareBarButtonItem, analyticSource: .productForm)
    }
}

// MARK: - Configuration
//
private extension ProductFormViewController {

    /// Configure navigation bar with the title
    ///
    func configureNavigationBar(title: String = "") {
        updateNavigationBar()
        updateBackButtonTitle()
        updateNavigationBarTitle()
    }

    func configureMainView() {
        view.backgroundColor = .basicBackground
    }

    func configureTableView() {
        registerTableViewCells()

        tableView.dataSource = tableViewDataSource
        tableView.delegate = self
        tableView.accessibilityIdentifier = "product-form"
        tableView.cellLayoutMarginsFollowReadableWidth = true

        tableView.backgroundColor = .listForeground(modal: false)
        tableView.removeLastCellSeparator()

        // Since the table view is in a container under a stack view, the safe area adjustment should be handled in the container view.
        tableView.contentInsetAdjustmentBehavior = .never

        tableView.reloadData()
    }

    /// Registers all of the available TableViewCells
    ///
    func registerTableViewCells() {
        tableViewModel.sections.forEach { section in
            switch section {
            case .primaryFields(let rows):
                rows.forEach { row in
                    row.cellTypes.forEach { cellType in
                        tableView.registerNib(for: cellType)
                    }
                }
            case .settings(let rows):
                rows.forEach { row in
                    row.cellTypes.forEach { cellType in
                        tableView.registerNib(for: cellType)
                    }
                }
            }
        }
    }

    func configurePresentationStyle() {
        switch presentationStyle {
        case .contained(let containerViewController):
            containerViewController()?.addCloseNavigationBarButton(target: self, action: #selector(closeNavigationBarButtonTapped))
        case .navigationStack:
            break
        }
    }

    func configureMoreDetailsContainerView() {
        let title = NSLocalizedString("Add more details", comment: "Title of the button at the bottom of the product form to add more product details.")
        let viewModel = BottomButtonContainerView.ViewModel(style: .link,
                                                            title: title,
                                                            image: .plusImage) { [weak self] button in
                                                                self?.moreDetailsButtonTapped(button: button)
        }
        let buttonContainerView = BottomButtonContainerView(viewModel: viewModel)

        moreDetailsContainerView.addSubview(buttonContainerView)
        moreDetailsContainerView.pinSubviewToAllEdges(buttonContainerView)
        moreDetailsContainerView.setContentCompressionResistancePriority(.required, for: .vertical)
        moreDetailsContainerView.setContentHuggingPriority(.required, for: .vertical)

        updateMoreDetailsButtonVisibility()
    }
}

// MARK: - Tooltip
//
private extension ProductFormViewController {
    func tooltipTargetPoint() -> CGPoint {
        guard let indexPath = findDescriptionAICellIndexPath() else {
            return .zero
        }

        guard let cell = tableView.cellForRow(at: indexPath),
              let buttonCell = cell as? ButtonTableViewCell,
              let imageView = buttonCell.button.imageView else {
            return .zero
        }

        let rectOfButtonInTableView = tableView.convert(buttonCell.button.frame, from: buttonCell)

        return CGPoint(
            x: rectOfButtonInTableView.minX + imageView.frame.midX,
            y: rectOfButtonInTableView.maxY
        )
    }

    func updateTooltipPresenter() {
        if let tooltipPresenter {
            tooltipPresenter.removeTooltip()
            self.tooltipPresenter = nil
        }

        guard tooltipUseCase.shouldShowTooltip(for: product) == true else {
            return
        }

        let tooltip = Tooltip(containerWidth: tableView.bounds.width)

        tooltip.title = Localization.AITooltip.title
        tooltip.message = Localization.AITooltip.message
        tooltip.primaryButtonTitle = Localization.AITooltip.gotIt
        tooltipPresenter = TooltipPresenter(
            containerView: tableView,
            tooltip: tooltip,
            target: .point(tooltipTargetPoint),
            primaryTooltipAction: { [weak self] in
                self?.tooltipUseCase.hasDismissedWriteWithAITooltip = true
            }
        )
        tooltipPresenter?.tooltipVerticalPosition = .below

        if isDescriptionAICellVisible() {
            tooltipPresenter?.showTooltip()
            didShowTooltip = true
        }
    }

    func isDescriptionAICellVisible() -> Bool {
        guard let indexPath = findDescriptionAICellIndexPath() else {
            return false
        }

        let cellRect = tableView.rectForRow(at: indexPath)
        return tableView.bounds.contains(cellRect)
    }

    func findDescriptionAICellIndexPath() -> IndexPath? {
        for (sectionIndex, section) in tableViewModel.sections.enumerated() {
            if case .primaryFields(rows: let sectionRows) = section {
                for (rowIndex, row) in sectionRows.enumerated() {
                    if case .descriptionAI = row {
                        return IndexPath(row: rowIndex, section: sectionIndex)
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Observations & responding to changes
//
private extension ProductFormViewController {
    func observeProduct() {
        productSubscription = viewModel.observableProduct.sink { [weak self] product in
            self?.onProductUpdated(product: product)
        }
    }

    /// Observe product name changes and re-render the product if the change happened outside this screen.
    ///
    /// This method covers the following case:
    /// 1. User changes the product name locally
    /// 2. User creates an attribute or a variation (This updates the whole product, overriding the unsaved product name)
    /// 3. ViewModel detects that there was a pending name change and fires an event to the name observable
    /// 4. View re-renders un-saved product name and updates the save button state.
    ///
    /// The "happened outside" condition is needed to not reload the view while the user is typing a new name.
    ///
    func observeProductName() {
        productNameSubscription = viewModel.productName?.sink { [weak self] _ in
            guard let self = self else { return }
            self.updateBackButtonTitle()
            if self.view.window == nil { // If window is nil, this screen isn't the active screen.
                self.onProductUpdated(product: self.product)
            }
        }
    }

    func observeUpdateCTAVisibility() {
        updateEnabledSubscription = viewModel.isUpdateEnabled.sink { [weak self] _ in
            self?.updateNavigationBar()
        }
    }

    /// Updates table rows when the price of the underlying variations change.
    /// Needed to show/hide the `.noPriceWarning` row.
    ///
    func observeVariationsPriceChanges() {
        newVariationsPriceSubscription = viewModel.newVariationsPrice.sink { [weak self] in
            self?.updateFormTableContent()
        }
    }

    /// Updates table rows when Blaze eligibility is computed.
    /// Needed to show/hide the "Promote with Blaze" button accordingly.
    ///
    func observeUpdateBlazeEligibility() {
        blazeEligibilitySubscription = viewModel.blazeEligibilityUpdate.sink { [weak self] in
            guard let self else { return }
            self.updateFormTableContent()
            if self.viewModel.canPromoteWithBlaze() && !self.viewModel.shouldShowBlazeIntroView {
                ServiceLocator.analytics.track(event: .Blaze.blazeEntryPointDisplayed(source: .productDetailPromoteButton))
            }
        }

    }

    /// Updates table view model and datasource.
    ///
    func reloadLinkedPromoCell() {
        tableViewModel = DefaultProductFormTableViewModel(product: viewModel.productModel,
                                                          actionsFactory: viewModel.actionsFactory,
                                                          currency: currency,
                                                          isDescriptionAIEnabled: aiEligibilityChecker.isFeatureEnabled(.description))

        reconfigureDataSource(tableViewModel: tableViewModel, statuses: productImageActionHandler.productImageStatuses)
    }

    func onProductUpdated(product: ProductModel) {
        updateMoreDetailsButtonVisibility()
        tableViewModel = DefaultProductFormTableViewModel(product: product,
                                                          actionsFactory: viewModel.actionsFactory,
                                                          currency: currency,
                                                          isDescriptionAIEnabled: aiEligibilityChecker.isFeatureEnabled(.description))
        reconfigureDataSource(tableViewModel: tableViewModel, statuses: productImageActionHandler.productImageStatuses)
    }

    func onImageStatusesUpdated(statuses: [ProductImageStatus]) {
        ///
        /// Why are we recreating the `tableViewModel`?
        ///
        /// When the user types and changes the product name, the `product` will change.
        /// But, we are NOT recreating `tableViewModel` and reloading the `tableView`
        /// to avoid reloading the cell while the user is still typing.
        ///
        /// The above scenario results in `tableViewModel` and `product` getting out of sync.
        /// i.e. `product` has name changed in it, but `tableViewModel` doesn’t reflect the "changed name".
        ///
        /// Now, if the user tries to add/edit images before saving the product name `onImageStatusesUpdated` is fired.
        ///
        /// If `onImageStatusesUpdated` calls `reconfigureDataSource` without recreating `tableViewModel`
        /// we end up showing old `product` information (old name in this case) in the `tableView`.
        ///
        /// By recreating `tableViewModel` using the latest `product` before calling `reconfigureDataSource`,
        /// we are making sure that we are not showing outdated `product` information in `tableView`.
        ///
        /// Note that the new name information isn’t lost. It lives inside `product`.
        /// If we recreate `tableViewModel` and reload using `reconfigureDataSource` we will have the new product name displayed in `tableView`.
        ///
        tableViewModel = DefaultProductFormTableViewModel(product: product,
                                                          actionsFactory: viewModel.actionsFactory,
                                                          currency: currency,
                                                          isDescriptionAIEnabled: aiEligibilityChecker.isFeatureEnabled(.description))
        reconfigureDataSource(tableViewModel: tableViewModel, statuses: statuses)
    }

    /// Recreates the `tableViewModel` and reloads the `table` & `datasource`.
    ///
    func updateFormTableContent() {
        tableViewModel = DefaultProductFormTableViewModel(product: product,
                                                          actionsFactory: viewModel.actionsFactory,
                                                          currency: currency,
                                                          isDescriptionAIEnabled: aiEligibilityChecker.isFeatureEnabled(.description))
        reconfigureDataSource(tableViewModel: tableViewModel, statuses: productImageActionHandler.productImageStatuses)
    }



    /// Recreates `tableViewDataSource` and reloads the `tableView` data.
    /// - Parameters:
    ///   - reloadClosure: custom tableView reload action, by default `reloadData()` will be triggered
    ///
    func reconfigureDataSource(tableViewModel: ProductFormTableViewModel, statuses: [ProductImageStatus], reloadClosure: (() -> Void)? = nil) {
        tableViewDataSource = ProductFormTableViewDataSource(viewModel: tableViewModel,
                                                             productImageStatuses: statuses,
                                                             productUIImageLoader: productUIImageLoader)
        updateDataSourceActions()
        tableView.dataSource = tableViewDataSource

        if let reloadClosure = reloadClosure {
            reloadClosure()
        } else {
            tableView.reloadData()
        }

        updateTooltipPresenter()
    }

    func updateDataSourceActions() {
        tableViewDataSource.openLinkedProductsAction = { [weak self] in
            self?.editLinkedProducts()
        }
        tableViewDataSource.reloadLinkedPromoAction = { [weak self] in
            guard let self = self else { return }
            self.reloadLinkedPromoCell()
        }
        tableViewDataSource.descriptionAIAction = { [weak self] in
            self?.showProductDescriptionAI()
        }
        tableViewDataSource.openAILegalPageAction = { [weak self] url in
            guard let self else { return }
            WebviewHelper.launch(url.absoluteString, with: self)
        }
        tableViewDataSource.configureActions(onNameChange: { [weak self] name in
            self?.onEditProductNameCompletion(newName: name ?? "")
        }, onStatusChange: { [weak self] isEnabled in
            self?.onEditStatusCompletion(isEnabled: isEnabled)
        }, onAddImage: { [weak self] in
            self?.eventLogger.logImageTapped()
            self?.showProductImages()
        })
    }
}

// MARK: More details actions
//
private extension ProductFormViewController {
    func moreDetailsButtonTapped(button: UIButton) {
        let title = NSLocalizedString("Add more details",
                                      comment: "Title of the bottom sheet from the product form to add more product details.")
        let viewProperties = BottomSheetListSelectorViewProperties(subtitle: title)
        let actions = viewModel.actionsFactory.bottomSheetActions()
        let dataSource = ProductFormBottomSheetListSelectorCommand(actions: actions) { [weak self] action in
                                                                    self?.dismiss(animated: true) { [weak self] in
                                                                        switch action {
                                                                        case .editInventorySettings:
                                                                            self?.eventLogger.logInventorySettingsTapped()
                                                                            self?.editInventorySettings()
                                                                        case .editShippingSettings:
                                                                            self?.eventLogger.logShippingSettingsTapped()
                                                                            self?.editShippingSettings()
                                                                        case .editCategories:
                                                                            ServiceLocator.analytics.track(.productDetailViewCategoriesTapped)
                                                                            self?.editCategories()
                                                                        case .editTags:
                                                                            ServiceLocator.analytics.track(.productDetailViewTagsTapped)
                                                                            self?.editTags()
                                                                        case .editShortDescription:
                                                                            ServiceLocator.analytics.track(.productDetailViewShortDescriptionTapped)
                                                                            self?.editShortDescription()
                                                                        case .editSKU:
                                                                            ServiceLocator.analytics.track(.productDetailViewSKUTapped)
                                                                            self?.editSKU()
                                                                        case .editLinkedProducts:
                                                                            ServiceLocator.analytics.track(.productDetailViewLinkedProductsTapped)
                                                                            self?.editLinkedProducts()
                                                                        case .editReviews:
                                                                            ServiceLocator.analytics.track(.productDetailViewReviewsTapped)
                                                                            self?.showReviews()
                                                                        case .editDownloadableFiles:
                                                                            ServiceLocator.analytics.track(.productDetailViewDownloadableFilesTapped)
                                                                            self?.showDownloadableFiles()
                                                                        }
                                                                    }
        }
        let listSelectorPresenter = BottomSheetListSelectorPresenter(viewProperties: viewProperties, command: dataSource)
        listSelectorPresenter.show(from: self, sourceView: button.titleLabel ?? button, arrowDirections: .down)
    }

    func updateMoreDetailsButtonVisibility() {
        let moreDetailsActions = viewModel.actionsFactory.bottomSheetActions()
        moreDetailsContainerView.isHidden = moreDetailsActions.isEmpty
    }
}

// MARK: Navigation actions
//
private extension ProductFormViewController {
    func saveProduct(status: ProductStatus? = nil, onCompletion: @escaping (Result<Void, ProductUpdateError>) -> Void = { _ in }) {
        let productStatus = status ?? product.status
        let messageType = viewModel.saveMessageType(for: productStatus)
        showSavingProgress(messageType)
        saveProductRemotely(status: status, onCompletion: onCompletion)
    }

    func saveProductRemotely(status: ProductStatus?, onCompletion: @escaping (Result<Void, ProductUpdateError>) -> Void = { _ in }) {
        let previousStatus = product.status
        let isNewProduct = !product.existsRemotely

        viewModel.saveProductRemotely(status: status) { [weak self] result in
            switch result {
            case .failure(let error):
                DDLogError("⛔️ Error updating Product: \(error)")

                // Dismisses the in-progress UI then presents the error alert.
                self?.navigationController?.dismiss(animated: true) {
                    self?.displayError(error: error)
                    onCompletion(.failure(error))
                }
            case .success:
                // Dismisses the in-progress UI
                self?.navigationController?.dismiss(animated: true, completion: nil)

                // Presents the confirmation alert
                let alertType: ProductSavedAlertType
                if status == .published && (isNewProduct || previousStatus != .published) {
                    alertType = .published
                } else if status == .draft || (status == nil && previousStatus == .draft) {
                    alertType = .draftSaved
                } else {
                    alertType = .saved
                }
                self?.presentProductConfirmationSaveAlert(type: alertType)

                // Show linked products promo banner after product save
                (self?.viewModel as? ProductFormViewModel)?.isLinkedProductsPromoEnabled = true
                self?.reloadLinkedPromoCell()
                onCompletion(.success(()))
            }
        }
    }

    func displayError(error: ProductUpdateError?, title: String = Localization.updateProductError) {
        let message = error?.errorDescription
        displayErrorAlert(title: title, message: message)
    }

    func displayErrorAlert(title: String?, message: String?) {
        let alert = UIAlertController(title: title,
                                      message: message,
                                      preferredStyle: .alert)
        let cancel = UIAlertAction(title: NSLocalizedString(
            "OK",
            comment: "Dismiss button on the alert when there is an error updating the product"
        ), style: .cancel, handler: nil)
        alert.addAction(cancel)

        present(alert, animated: true, completion: nil)
    }

    func displayWebViewForProductInStore() {
        guard let url = URL(string: product.permalink) else {
            return
        }
        WebviewHelper.launch(url, with: self)
    }

    func displayShareProduct(from sourceView: UIBarButtonItem, analyticSource: WooAnalyticsEvent.ProductForm.ShareProductSource) {
        ServiceLocator.analytics.track(event: .ProductForm.productDetailShareButtonTapped(source: analyticSource))

        guard let url = URL(string: product.permalink),
              let navigationController = self.navigationController else {
            return
        }

        let shareProductCoordinator = ShareProductCoordinator(siteID: product.siteID,
                                                              productURL: url,
                                                              productName: product.name,
                                                              productDescription: product.description ?? product.shortDescription ?? "",
                                                              shareSheetAnchorItem: sourceView,
                                                              navigationController: navigationController)
        shareProductCoordinator.start()
        self.shareProductCoordinator = shareProductCoordinator
    }

    func duplicateProduct() {
        showSavingProgress(.duplicate)
        viewModel.duplicateProduct(onCompletion: { [weak self] result in
            switch result {
            case .failure(let error):
                DDLogError("⛔️ Error duplicating Product: \(error)")

                // Dismisses the in-progress UI then presents the error alert.
                self?.navigationController?.dismiss(animated: true) {
                    self?.displayError(error: error, title: Localization.duplicateProductError)
                }
            case .success:
                // Dismisses the in-progress UI, then presents the confirmation alert.
                self?.navigationController?.dismiss(animated: true) {
                    self?.presentProductConfirmationSaveAlert(type: .copied)
                }
            }
        })
    }

    func displayDeleteProductAlert() {
        let showVariationsText = viewModel is ProductVariationFormViewModel
        if showVariationsText {
            presentVariationConfirmationDeleteAlert { [weak self] isConfirmed in
                guard isConfirmed else {
                    return
                }

                self?.trackVariationRemoveButtonTapped()
                self?.showVariationDeletionProgress()
                self?.deleteProduct()
            }
        } else {
            presentProductConfirmationDeleteAlert { [weak self] isConfirmed in
                guard isConfirmed else {
                    return
                }

                self?.showProductDeletionProgress()
                self?.deleteProduct()
            }
        }
    }

    func deleteProduct() {
        self.viewModel.deleteProductRemotely { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                ServiceLocator.analytics.track(.productDetailProductDeleted)
                // Dismisses the in-progress UI.
                self.navigationController?.dismiss(animated: true, completion: nil)
                // Dismiss or Pop the Product Form
                self.dismissOrPopViewController()
                self.onDeleteCompletion()
            case .failure(let error):
                DDLogError("⛔️ Error deleting Product: \(error)")

                // Dismisses the in-progress UI then presents the error alert.
                self.navigationController?.dismiss(animated: true) { [weak self] in
                    self?.displayError(error: error)
                }
            }
        }
    }

    func displayProductSettings() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let viewController = ProductSettingsViewController(product: product.product,
                                                           password: password,
                                                           formType: viewModel.formType,
                                                           completion: { [weak self] (productSettings) in
            guard let self = self else {
                return
            }
            self.viewModel.updateProductSettings(productSettings)
        }, onPasswordRetrieved: { [weak self] (originalPassword) in
            self?.viewModel.resetPassword(originalPassword)
        })
        navigationController?.pushViewController(viewController, animated: true)
    }

    func displayBlaze() {
        guard let site = ServiceLocator.stores.sessionManager.defaultSite else {
            return
        }

        guard let navigationController else {
            DDLogError("⛔️ Missing parent controller to show Blaze campaign creation form.")
            return
        }

        let coordinator = BlazeCampaignCreationCoordinator(
            siteID: site.siteID,
            siteURL: site.url,
            productID: product.productID,
            source: .productDetailPromoteButton,
            shouldShowIntro: viewModel.shouldShowBlazeIntroView,
            navigationController: navigationController,
            onCampaignCreated: { [weak self] in
                /// Re-sync Blaze campaigns to update storage items.
                ServiceLocator.stores.dispatch(BlazeAction.synchronizeCampaignsList(
                    siteID: site.siteID,
                    skip: 0,
                    limit: PaginationTracker.Defaults.pageSize) { _ in
                        self?.updateFormTableContent()
                    }
                )
            }
        )
        coordinator.start()
        blazeCampaignCreationCoordinator = coordinator
    }

    func trackVariationRemoveButtonTapped() {
        guard let variation = (product as? EditableProductVariationModel)?.productVariation else {
            return
        }

        ServiceLocator.analytics.track(event: WooAnalyticsEvent.Variations.removeVariationButtonTapped(productID: variation.productID,
                                                                                                       variationID: variation.productVariationID))
    }

    func trackEditVariationAttributesRowTapped() {
        guard let variation = (product as? EditableProductVariationModel)?.productVariation else {
            return
        }

        ServiceLocator.analytics.track(event: WooAnalyticsEvent.Variations.editVariationAttributeOptionsRowTapped(productID: variation.productID,
                                                                                                                  variationID: variation.productVariationID))
    }

    func trackEditProductAttributeRowTapped() {
        ServiceLocator.analytics.track(event: WooAnalyticsEvent.Variations.editAttributesButtonTapped(productID: product.productID))
    }
}

// MARK: Navigation Bar Items
//
private extension ProductFormViewController {

    /// Even if the back button don't show any text, we still need a back button title for the menu that is presented by long pressing the back button.
    ///
    func updateBackButtonTitle() {
        navigationItem.backButtonTitle = viewModel.productModel.name.isNotEmpty ? viewModel.productModel.name : Localization.unnamedProduct
    }

    func updateNavigationBarTitle() {
        guard traitCollection.horizontalSizeClass != .compact else {
            title = nil
            return
        }
        // Update navigation bar title with variation ID for variation page
        guard let variationID = viewModel.productionVariationID else {
            title = Localization.defaultTitle
            return
        }
        title = Localization.variationViewTitle(variationID: "\(variationID)")
    }

    func updateNavigationBar() {
        // Create action buttons based on view model
        let rightBarButtonItems: [UIBarButtonItem] = viewModel.actionButtons.reversed().map { buttonType in
            switch buttonType {
            case .preview:
                return createPreviewBarButtonItem()
            case .publish:
                return createPublishBarButtonItem()
            case .save:
                return createSaveBarButtonItem()
            case .more:
                return createMoreOptionsBarButtonItem()
            case .share:
                return shareBarButtonItem
            }
        }

        navigationItem.rightBarButtonItems = rightBarButtonItems
        switch presentationStyle {
        case .contained(let containerViewController):
            containerViewController()?.navigationItem.rightBarButtonItems = rightBarButtonItems
        default:
            break
        }
    }

    func createPublishBarButtonItem() -> UIBarButtonItem {
        let publishButton = UIBarButtonItem(title: Localization.publishTitle,
                                            style: .done,
                                            target: self,
                                            action: #selector(publishProduct))
        publishButton.accessibilityIdentifier = "publish-product-button"
        return publishButton
    }

    func createSaveBarButtonItem() -> UIBarButtonItem {
        let saveButton = UIBarButtonItem(title: Localization.saveTitle,
                                         style: .done,
                                         target: self,
                                         action: #selector(saveProductAndLogEvent))
        saveButton.accessibilityIdentifier = "save-product-button"
        return saveButton
    }

    func createPreviewBarButtonItem() -> UIBarButtonItem {
        let previewButton = UIBarButtonItem(title: Localization.previewTitle, style: .done, target: self, action: #selector(saveDraftAndDisplayProductPreview))
        previewButton.isEnabled = viewModel.shouldEnablePreviewButton()
        return previewButton
    }

    func createMoreOptionsBarButtonItem() -> UIBarButtonItem {
        let moreButton = UIBarButtonItem(image: .moreImage,
                                     style: .plain,
                                     target: self,
                                     action: #selector(presentMoreOptionsActionSheet(_:)))
        moreButton.accessibilityLabel = NSLocalizedString("More options", comment: "Accessibility label for the Edit Product More Options action sheet")
        moreButton.accessibilityIdentifier = "edit-product-more-options-button"
        return moreButton
    }
}

// MARK: - Keyboard management
//
private extension ProductFormViewController {
    /// Registers for all of the related Notifications
    ///
    func startListeningToNotifications() {
        keyboardFrameObserver.startObservingKeyboardFrame()
    }
}

extension ProductFormViewController: KeyboardScrollable {
    var scrollable: UIScrollView {
        return tableView
    }
}

// MARK: - Helper Methods

private extension ProductFormViewController {

    /// Presents a URL modally.
    ///
    func presentURL(_ url: URL) {
        let safariViewController = SFSafariViewController(url: url)
        present(safariViewController, animated: true)
    }
}

// MARK: - Navigation actions handling
//
private extension ProductFormViewController {
    func presentBackNavigationActionSheet(onDiscard: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}) {
        let exitForm: () -> Void = {
            presentationStyle.createExitForm(viewController: navigationController ?? self, completion: onDiscard)
        }()
        let viewControllerToPresentAlert = navigationController?.topViewController ?? self
        switch viewModel.formType {
        case .add:
            UIAlertController.presentDiscardNewProductActionSheet(viewController: viewControllerToPresentAlert,
                                                                  onSaveDraft: { [weak self] in
                self?.saveProductAsDraft()
            }, onDiscard: {
                exitForm()
            }, onCancel: {
                onCancel()
            })
        case .edit:
            UIAlertController.presentDiscardChangesActionSheet(viewController: viewControllerToPresentAlert,
                                                               onDiscard: {
                exitForm()
            }, onCancel: {
                onCancel()
            })
        case .readonly:
            break
        }
    }
}

// MARK: Action - Edit Product Images
//
private extension ProductFormViewController {
    func showProductImages() {
        let imagesViewController = ProductImagesViewController(product: product,
                                                               productImageActionHandler: productImageActionHandler,
                                                               productUIImageLoader: productUIImageLoader) { [weak self] images, hasChangedData in
                                                                self?.onEditProductImagesCompletion(images: images, hasChangedData: hasChangedData)
        }
        navigationController?.pushViewController(imagesViewController, animated: true)
    }

    func onEditProductImagesCompletion(images: [ProductImage], hasChangedData: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        ServiceLocator.analytics.track(.productImageSettingsDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])
        guard hasChangedData else {
            return
        }
        self.viewModel.updateImages(images)
    }
}

// MARK: Action - Edit Product Name
//
private extension ProductFormViewController {
    func onEditProductNameCompletion(newName: String) {
        viewModel.updateName(newName)

        /// This refresh is used to adapt the size of the cell to the text
        tableView.beginUpdates()
        tableView.endUpdates()
    }
}

// MARK: Action - Edit Product Description
//
private extension ProductFormViewController {
    func editProductDescription() {
        let isAIGenerationEnabled = aiEligibilityChecker.isFeatureEnabled(.description)
        let editorViewController = EditorFactory().productDescriptionEditor(product: product,
                                                                            isAIGenerationEnabled: isAIGenerationEnabled) { [weak self] content, productName in
            guard let self else { return }
            defer {
                self.navigationController?.popViewController(animated: true)
            }
            if let productName {
                self.onEditProductNameCompletion(newName: productName)
            }
            self.onEditProductDescriptionCompletion(newDescription: content)
        }
        navigationController?.pushViewController(editorViewController, animated: true)
    }

    func onEditProductDescriptionCompletion(newDescription: String) {
        let hasChangedData = newDescription != product.description
        ServiceLocator.analytics.track(.productDescriptionDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])

        guard hasChangedData else {
            return
        }
        viewModel.updateDescription(newDescription)
    }
}

// MARK: Action - Product Description AI
//
private extension ProductFormViewController {
    func showProductDescriptionAI() {
        guard let navigationController else {
            return
        }
        let coordinator = ProductDescriptionAICoordinator(product: product,
                                                          navigationController: navigationController,
                                                          source: .productForm,
                                                          analytics: ServiceLocator.analytics,
                                                          onApply: { [weak self] output in
            guard let self else { return }
            self.onEditProductNameCompletion(newName: output.name)
            self.onEditProductDescriptionCompletion(newDescription: output.description)
        })
        descriptionAICoordinator = coordinator
        coordinator.start()
    }
}

// MARK: Action - Edit Product Price Settings
//
private extension ProductFormViewController {
    func editPriceSettings() {
        let priceSettingsViewController = ProductPriceSettingsViewController(product: product) { [weak self] in
            self?.onEditPriceSettingsCompletion(regularPrice: $0,
                                                subscriptionPeriod: $1,
                                                subscriptionPeriodInterval: $2,
                                                subscriptionSignupFee: $3,
                                                salePrice: $4,
                                                dateOnSaleStart: $5,
                                                dateOnSaleEnd: $6,
                                                taxStatus: $7,
                                                taxClass: $8,
                                                hasUnsavedChanges: $9)
        }
        navigationController?.pushViewController(priceSettingsViewController, animated: true)
    }

    func onEditPriceSettingsCompletion(regularPrice: String?,
                                       subscriptionPeriod: SubscriptionPeriod?,
                                       subscriptionPeriodInterval: String?,
                                       subscriptionSignupFee: String?,
                                       salePrice: String?,
                                       dateOnSaleStart: Date?,
                                       dateOnSaleEnd: Date?,
                                       taxStatus: ProductTaxStatus,
                                       taxClass: TaxClass?,
                                       hasUnsavedChanges: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }

        ServiceLocator.analytics.track(.productPriceSettingsDoneButtonTapped, withProperties: ["has_changed_data": hasUnsavedChanges])
        guard hasUnsavedChanges else {
            return
        }

        viewModel.updatePriceSettings(regularPrice: regularPrice,
                                      subscriptionPeriod: subscriptionPeriod,
                                      subscriptionPeriodInterval: subscriptionPeriodInterval,
                                      subscriptionSignupFee: subscriptionSignupFee,
                                      salePrice: salePrice,
                                      dateOnSaleStart: dateOnSaleStart,
                                      dateOnSaleEnd: dateOnSaleEnd,
                                      taxStatus: taxStatus,
                                      taxClass: taxClass)
    }
}

// MARK: Action - Show Product Reviews Settings
//
private extension ProductFormViewController {
    func showReviews() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let productReviewsViewController = ProductReviewsViewController(product: product.product)
        navigationController?.show(productReviewsViewController, sender: self)
    }
}

// MARK: Action - Edit Product Type Settings
//
private extension ProductFormViewController {
    func editProductType(cell: UITableViewCell?) {
        let title = NSLocalizedString("Change product type",
                                      comment: "Message title of bottom sheet for selecting a product type")
        let viewProperties = BottomSheetListSelectorViewProperties(subtitle: title)
        let productType = BottomSheetProductType(productType: viewModel.productModel.productType, isVirtual: viewModel.productModel.virtual)
        let command = ProductTypeBottomSheetListSelectorCommand(
            source: .editForm(selected: productType),
            subscriptionProductsEligibilityChecker: subscriptionProductsEligibilityChecker
        ) { [weak self] (selectedProductType) in
            self?.dismiss(animated: true, completion: nil)

            guard let originalProductType = self?.product.productType else {
                return
            }

            ServiceLocator.analytics.track(.productTypeChanged, withProperties: [
                "from": originalProductType.rawValue,
                "to": selectedProductType.productType.rawValue
            ])

            self?.presentProductTypeChangeAlert(for: originalProductType, completion: { (change) in
                guard change == true else {
                    return
                }
                self?.viewModel.updateProductType(productType: selectedProductType)
            })
        }
        let productTypesListPresenter = BottomSheetListSelectorPresenter(viewProperties: viewProperties, command: command)
        productTypesListPresenter.show(from: self, sourceView: cell, arrowDirections: .any)
    }
}

// MARK: Action - Edit Product Shipping Settings
//
private extension ProductFormViewController {
    func editShippingSettings() {
        let shippingSettingsViewController = ProductShippingSettingsViewController(product: product) {
            [weak self] (weight, dimensions, oneTimeShipping, shippingClass, shippingClassID, hasUnsavedChanges) in
            self?.onEditShippingSettingsCompletion(weight: weight,
                                                   dimensions: dimensions,
                                                   oneTimeShipping: oneTimeShipping,
                                                   shippingClass: shippingClass,
                                                   shippingClassID: shippingClassID,
                                                   hasUnsavedChanges: hasUnsavedChanges)
        }
        navigationController?.pushViewController(shippingSettingsViewController, animated: true)
    }

    func onEditShippingSettingsCompletion(weight: String?,
                                          dimensions: ProductDimensions,
                                          oneTimeShipping: Bool?,
                                          shippingClass: String?,
                                          shippingClassID: Int64?,
                                          hasUnsavedChanges: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        ServiceLocator.analytics.track(.productShippingSettingsDoneButtonTapped, withProperties: ["has_changed_data": hasUnsavedChanges])

        guard hasUnsavedChanges else {
            return
        }
        viewModel.updateShippingSettings(weight: weight,
                                         dimensions: dimensions,
                                         oneTimeShipping: oneTimeShipping,
                                         shippingClass: shippingClass,
                                         shippingClassID: shippingClassID)
    }
}

// MARK: Action - Edit Product Inventory Settings
//
private extension ProductFormViewController {
    func editInventorySettings() {
        let inventorySettingsViewController = ProductInventorySettingsViewController(product: product) { [weak self] data in
            self?.onEditInventorySettingsCompletion(data: data)
        }
        navigationController?.pushViewController(inventorySettingsViewController, animated: true)
    }

    func onEditInventorySettingsCompletion(data: ProductInventoryEditableData) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        let originalData = ProductInventoryEditableData(productModel: product)
        let hasChangedData = originalData != data

        ServiceLocator.analytics.track(.productInventorySettingsDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])

        guard hasChangedData else {
            return
        }
        viewModel.updateInventorySettings(sku: data.sku,
                                          manageStock: data.manageStock,
                                          soldIndividually: data.soldIndividually,
                                          stockQuantity: data.stockQuantity,
                                          backordersSetting: data.backordersSetting,
                                          stockStatus: data.stockStatus)
    }
}

// MARK: Action - Edit Product Short Description
//
private extension ProductFormViewController {
    func editShortDescription() {
        let editorViewController = EditorFactory().productShortDescriptionEditor(product: product) { [weak self] content, _ in
            self?.onEditShortDescriptionCompletion(newShortDescription: content)
        }
        navigationController?.pushViewController(editorViewController, animated: true)
    }

    func onEditShortDescriptionCompletion(newShortDescription: String) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = newShortDescription != product.shortDescription
        ServiceLocator.analytics.track(.productShortDescriptionDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])

        guard hasChangedData else {
            return
        }
        viewModel.updateShortDescription(newShortDescription)
    }
}

// MARK: Action - Edit Product Categories
//

private extension ProductFormViewController {
    func editCategories() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let categoryListViewController = EditProductCategoryListViewController(product: product.product) { [weak self] (categories) in
            self?.onEditCategoriesCompletion(categories: categories)
        }
        show(categoryListViewController, sender: self)
    }

    func onEditCategoriesCompletion(categories: [ProductCategory]) {
        guard let product = product as? EditableProductModel else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = categories.sorted() != product.product.categories.sorted()
        guard hasChangedData else {
            return
        }
        viewModel.updateProductCategories(categories)
    }
}

// MARK: Action - Edit Product Tags
//

private extension ProductFormViewController {
    func editTags() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let tagsViewController = ProductTagsViewController(product: product.product) { [weak self] (tags) in
            self?.onEditTagsCompletion(tags: tags)
        }
        show(tagsViewController, sender: self)
    }

    func onEditTagsCompletion(tags: [ProductTag]) {
        guard let product = product as? EditableProductModel else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = tags.sorted() != product.product.tags.sorted()
        guard hasChangedData else {
            return
        }
        viewModel.updateProductTags(tags)
    }
}

// MARK: Action - Edit Product SKU
//
private extension ProductFormViewController {
    func editSKU() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let viewController = ProductInventorySettingsViewController(product: product, formType: .sku) { [weak self] data in
            self?.onEditSKUCompletion(sku: data.sku)
        }
        show(viewController, sender: self)
    }

    func onEditSKUCompletion(sku: String?) {
        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = sku != product.sku
        ServiceLocator.analytics.track(.productSKUDoneButtonTapped, withProperties: ["has_changed_data": hasChangedData])
        guard hasChangedData else {
            return
        }
        viewModel.updateSKU(sku)
    }
}

// MARK: Action - Edit Linked Products
//
private extension ProductFormViewController {
    func editLinkedProducts() {
        let linkedProductsViewController = LinkedProductsViewController(product: product) { [weak self] (upsellIDs, crossSellIDs, hasUnsavedChanges) in
            self?.onEditLinkedProductsCompletion(upsellIDs: upsellIDs, crossSellIDs: crossSellIDs, hasUnsavedChanges: hasUnsavedChanges)
        }
        navigationController?.pushViewController(linkedProductsViewController, animated: true)
    }

    func onEditLinkedProductsCompletion(upsellIDs: [Int64],
                                        crossSellIDs: [Int64],
                                        hasUnsavedChanges: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }

        guard hasUnsavedChanges else {
            return
        }
        ServiceLocator.analytics.track(.linkedProducts, withProperties: ["action": "done"])

        viewModel.updateLinkedProducts(upsellIDs: upsellIDs, crossSellIDs: crossSellIDs)
    }
}

// MARK: Action - Edit Grouped Products (Grouped Products Only)
//
private extension ProductFormViewController {
    func editGroupedProducts() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let viewConfiguration = LinkedProductsListSelectorViewController.ViewConfiguration(title: Localization.groupedProductsViewTitle,
                                                                                           trackingContext: "grouped_products")

        let viewController = LinkedProductsListSelectorViewController(product: product.product,
                                                                      linkedProductIDs: product.product.groupedProducts,
                                                                      viewConfiguration: viewConfiguration) { [weak self] groupedProductIDs in
            self?.onEditGroupedProductsCompletion(groupedProductIDs: groupedProductIDs)
        }
        show(viewController, sender: self)
    }

    func onEditGroupedProductsCompletion(groupedProductIDs: [Int64]) {
        guard let product = product as? EditableProductModel else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = groupedProductIDs != product.product.groupedProducts
        guard hasChangedData else {
            return
        }
        viewModel.updateGroupedProductIDs(groupedProductIDs)
    }
}

// MARK: Action - Edit Product External Link
//
private extension ProductFormViewController {
    func editExternalLink() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let viewController = ProductExternalLinkViewController(product: product.product) { [weak self] externalURL, buttonText in
            self?.onEditExternalLinkCompletion(externalURL: externalURL, buttonText: buttonText)
        }
        show(viewController, sender: self)
    }

    func onEditExternalLinkCompletion(externalURL: String?, buttonText: String) {
        guard let product = product as? EditableProductModel else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }
        let hasChangedData = externalURL != product.product.externalURL || buttonText != product.product.buttonText
        guard hasChangedData else {
            return
        }
        viewModel.updateExternalLink(externalURL: externalURL, buttonText: buttonText)
    }
}

// MARK: Action - Edit Status (Enabled/Disabled)
//
private extension ProductFormViewController {
    func onEditStatusCompletion(isEnabled: Bool) {
        viewModel.updateStatus(isEnabled)
    }
}

// MARK: Action - Edit Product Downloads
//
private extension ProductFormViewController {
    func showDownloadableFiles() {
        guard let product = product as? EditableProductModel else {
            return
        }

        let downloadFileListViewController = ProductDownloadListViewController(product: product) { [weak self] (data, hasUnsavedChanges) in
            self?.onAddEditDownloadsCompletion(data: data, hasUnsavedChanges: hasUnsavedChanges)
        }
        navigationController?.pushViewController(downloadFileListViewController, animated: true)
    }

    func onAddEditDownloadsCompletion(data: ProductDownloadsEditableData,
                                      hasUnsavedChanges: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }

        guard hasUnsavedChanges else {
            return
        }
        viewModel.updateDownloadableFiles(downloadableFiles: data.downloadableFiles, downloadLimit: data.downloadLimit, downloadExpiry: data.downloadExpiry)
    }
}

// MARK: Action - Edit Product Variation Attributes
//
private extension ProductFormViewController {
    /// Edit the product attributes or the variation attributes depending on the product model type.
    ///
    func editAttributes() {
        switch product {
        case is EditableProductModel:
            editProductAttributes()
            trackEditProductAttributeRowTapped()
        case is EditableProductVariationModel:
            editVariationAttributes()
            trackEditVariationAttributesRowTapped()
        default:
            break
        }
    }

    /// Navigate to edit product attributes
    ///
    func editProductAttributes() {
        guard let productModel = product as? EditableProductModel else {
            return
        }
        let attributesViewModel = EditAttributesViewModel(product: productModel.product, allowVariationCreation: false)
        let attributesViewController = EditAttributesViewController(viewModel: attributesViewModel)
        attributesViewController.onAttributesUpdate = { [weak self] updatedProduct in
            self?.onAttributeUpdated(attributesViewController: attributesViewController, updatedProduct: updatedProduct)
        }
        show(attributesViewController, sender: self)
    }

    func editVariationAttributes() {
        guard let productVariationModel = product as? EditableProductVariationModel else {
            return
        }

        let attributePickerViewController = AttributePickerViewController(variationModel: productVariationModel) { [weak self] (attributes) in
            self?.onEditVariationAttributesCompletion(attributes: attributes)
        }
        show(attributePickerViewController, sender: self)
    }

    func onEditVariationAttributesCompletion(attributes: [ProductVariationAttribute]) {
        guard let productVariation = product as? EditableProductVariationModel else {
            return
        }

        defer {
            navigationController?.popViewController(animated: true)
        }

        let hasChangedData = attributes != productVariation.productVariation.attributes
        guard hasChangedData else {
            return
        }
        viewModel.updateVariationAttributes(attributes)
    }

    /// Perform necessary actions when an attribute is created or updated.
    ///
    func onAttributeUpdated(attributesViewController: UIViewController, updatedProduct: Product) {
        viewModel.updateProductVariations(from: updatedProduct)
        navigationController?.popToViewController(attributesViewController, animated: true)
    }
}

// MARK: Action - View Add-ons
//
private extension ProductFormViewController {
    func navigateToAddOns() {
        guard let product = product as? EditableProductModel else {
            return
        }
        let viewModel = ProductAddOnsListViewModel(addOns: product.product.addOns)
        let viewController = ProductAddOnsListViewController(viewModel: viewModel)
        show(viewController, sender: self)
    }
}

// MARK: Action - Show Product Variations
//
private extension ProductFormViewController {
    func showVariations() {
        guard let currentProduct = viewModel.productModel as? EditableProductModel else {
            return
        }
        let variationsViewModel = ProductVariationsViewModel(formType: viewModel.formType)
        let variationsViewController = ProductVariationsViewController(initialViewController: self,
                                                                       viewModel: variationsViewModel,
                                                                       product: currentProduct.product)
        variationsViewController.onProductUpdate = { [viewModel] updatedProduct in
            viewModel.updateProductVariations(from: updatedProduct)
        }
        show(variationsViewController, sender: self)
    }
}

// MARK: Action - Show Bundled Products
//
private extension ProductFormViewController {
    func showBundledProducts() {
        guard let product = product as? EditableProductModel else {
            return
        }
        let viewModel = BundledProductsListViewModel(siteID: product.siteID, bundleItems: product.bundledItems)
        let viewController = BundledProductsListViewController(viewModel: viewModel)
        show(viewController, sender: self)
    }
}

// MARK: Action - Show Composite Product Components
//
private extension ProductFormViewController {
    func showCompositeComponents() {
        guard let product = product as? EditableProductModel else {
            return
        }
        let viewModel = ComponentsListViewModel(siteID: product.siteID, components: product.compositeComponents)
        let viewController = ComponentsListViewController(viewModel: viewModel)
        show(viewController, sender: self)
    }
}

// MARK: Action - Show Subscription Free trial Settings
//
private extension ProductFormViewController {
    func showSubscriptionFreeTrialSettings() {
        guard let subscription = product.subscription else {
            return
        }
        let viewModel = SubscriptionTrialViewModel(subscription: subscription) { [weak self] trialLength, trialPeriod, hasUnsavedChanges in
            self?.onEditSubscriptionFreeTrialSettings(trialLength: trialLength,
                                                      trialPeriod: trialPeriod,
                                                      hasUnsavedChanges: hasUnsavedChanges)
        }
        let viewController = SubscriptionTrialViewController(viewModel: viewModel)
        show(viewController, sender: self)
    }

    func onEditSubscriptionFreeTrialSettings(trialLength: String,
                                             trialPeriod: SubscriptionPeriod,
                                             hasUnsavedChanges: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }

        ServiceLocator.analytics.track(event: .ProductDetail.freeTrialDetailsScreenClosed(hasChangedData: hasUnsavedChanges))

        guard hasUnsavedChanges else {
            return
        }
        viewModel.updateSubscriptionFreeTrialSettings(trialLength: trialLength,
                                                      trialPeriod: trialPeriod)
    }
}

// MARK: Action - Show Subscription expiry settings
//
private extension ProductFormViewController {
    func showSubscriptionExpirySettings() {
        guard let subscription = product.subscription else {
            return
        }
        let viewModel = SubscriptionExpiryViewModel(subscription: subscription) { [weak self] length, hasUnsavedChanges in
            self?.onEditSubscriptionExpirySettings(length: length,
                                                   hasUnsavedChanges: hasUnsavedChanges)
        }
        let viewController = SubscriptionExpiryViewController(viewModel: viewModel)
        show(viewController, sender: self)
    }

    func onEditSubscriptionExpirySettings(length: String,
                                          hasUnsavedChanges: Bool) {
        defer {
            navigationController?.popViewController(animated: true)
        }

        ServiceLocator.analytics.track(event: .ProductDetail.expirationDetailsScreenClosed(hasChangedData: hasUnsavedChanges))

        guard hasUnsavedChanges else {
            return
        }
        viewModel.updateSubscriptionExpirySettings(length: length)
    }
}

// MARK: Action - Show Quantity Rules
//
private extension ProductFormViewController {
    func showQuantityRules() {
        let quantityRulesViewModel = QuantityRulesViewModel(product: product) { [weak self] rules, hasUnsavedChanges in
            defer {
                self?.navigationController?.popViewController(animated: true)
            }

            self?.eventLogger.logQuantityRulesDoneButtonTapped(hasUnsavedChanges: hasUnsavedChanges)

            guard hasUnsavedChanges else {
                return
            }

            self?.viewModel.updateQuantityRules(minQuantity: rules.minQuantity, maxQuantity: rules.maxQuantity, groupOf: rules.groupOf)
        }
        let viewController = QuantityRulesViewController(viewModel: quantityRulesViewModel)
        show(viewController, sender: self)
    }
}

// MARK: Constants
//
private enum Localization {
    static let share = NSLocalizedString("Share", comment: "Action for sharing a product from the product details screen")
    static let publishTitle = NSLocalizedString("Publish", comment: "Action for creating a new product remotely with a published status")
    static let saveTitle = NSLocalizedString("Save", comment: "Action for saving a Product remotely")
    static let previewTitle = NSLocalizedString("Preview", comment: "Action for previewing draft Product changes in the webview")
    static let groupedProductsViewTitle = NSLocalizedString("Grouped Products",
                                                            comment: "Navigation bar title for editing linked products for a grouped product")
    static let unnamedProduct = NSLocalizedString("Unnamed product",
                                                  comment: "Back button title when the product doesn't have a name")

    static func variationViewTitle(variationID: String) -> String {
        let titleFormat = NSLocalizedString("Variation #%1$@", comment: "Navigation bar title for variation. Parameters: %1$@ - Product variation ID")
        return String.localizedStringWithFormat(titleFormat, variationID)
    }
    static let updateProductError = NSLocalizedString("Cannot update product", comment: "The title of the alert when there is an error updating the product")
    static let duplicateProductError = NSLocalizedString(
        "Cannot duplicate product",
        comment: "The title of the alert when there is an error duplicating the product"
    )
    static let defaultTitle = NSLocalizedString("productForm.defaultTitle", value: "Product", comment: "Product title")

    enum AITooltip {
        static let title = NSLocalizedString("Write with AI",
                                             comment: "The title of the Write with AI tooltip")
        static let message = NSLocalizedString("Use our AI-powered tool to quickly generate product descriptions. Just input keywords and we'll do the rest!",
                                               comment: "The message for the Write with AI tooltip")
        static let gotIt = NSLocalizedString("Got it",
                                             comment: "Button title that dismisses the Write with AI tooltip")
    }
}

private enum URLs {
    static let wpComPrivacySettings = URL(string: "https://wordpress.com/support/privacy-settings/")!
}

private enum ActionSheetStrings {
    static let saveProductAsDraft = NSLocalizedString("Save as draft",
                                                      comment: "Button title to save a product as draft in Product More Options Action Sheet")
    static let viewProduct = NSLocalizedString("View Product in Store",
                                               comment: "Button title View product in store in Edit Product More Options Action Sheet")
    static let share = NSLocalizedString("Share", comment: "Button title Share in Edit Product More Options Action Sheet")
    static let promoteWithBlaze = NSLocalizedString("Promote with Blaze", comment: "Button title Promote with Blaze in Edit Product More Options Action Sheet")
    static let trashProduct = NSLocalizedString("productForm.bottomSheet.trashAction",
                                                value: "Trash product",
                                                comment: "Button title Trash product in Edit Product More Options Action Sheet")
    static let productSettings = NSLocalizedString("Product Settings", comment: "Button title Product Settings in Edit Product More Options Action Sheet")
    static let cancel = NSLocalizedString("Cancel", comment: "Button title Cancel in Edit Product More Options Action Sheet")
    static let duplicate = NSLocalizedString("Duplicate", comment: "Button title to duplicate a product in Product More Options Action Sheet")
}
