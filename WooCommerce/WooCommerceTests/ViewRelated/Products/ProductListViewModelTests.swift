import XCTest
import Yosemite
import Fakes
@testable import WooCommerce

@MainActor
final class ProductListViewModelTests: XCTestCase {
    private let sampleSiteID: Int64 = 123
    private var storesManager: MockStoresManager!

    override func setUp() {
        super.setUp()
        storesManager = MockStoresManager(sessionManager: .makeForTesting())
    }

    override func tearDown() {
        storesManager = nil
        super.tearDown()
    }

    func test_selecting_and_deselecting_product_and_checking_its_state_works() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1)
        XCTAssertFalse(viewModel.productIsSelected(sampleProduct1))

        // When
        viewModel.selectProduct(sampleProduct1)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 1)
        XCTAssertTrue(viewModel.productIsSelected(sampleProduct1))

        // When
        viewModel.deselectProduct(sampleProduct1)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 0)
        XCTAssertFalse(viewModel.productIsSelected(sampleProduct1))
    }

    func test_selecting_multiple_products_works() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1)
        let sampleProduct2 = Product.fake().copy(productID: 2)
        let sampleProduct3 = Product.fake().copy(productID: 3)
        XCTAssertEqual(viewModel.selectedProductsCount, 0)

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProducts([sampleProduct2, sampleProduct3])

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 3)
        XCTAssertTrue(viewModel.productIsSelected(sampleProduct1))
        XCTAssertTrue(viewModel.productIsSelected(sampleProduct2))
        XCTAssertTrue(viewModel.productIsSelected(sampleProduct3))
    }

    func test_deselecting_not_selected_product_does_nothing() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1)
        let sampleProduct2 = Product.fake().copy(productID: 2)
        XCTAssertEqual(viewModel.selectedProductsCount, 0)

        // When
        viewModel.deselectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 1)
        XCTAssertFalse(viewModel.productIsSelected(sampleProduct1))
        XCTAssertTrue(viewModel.productIsSelected(sampleProduct2))
    }

    func test_selecting_and_deselecting_product_twice_is_ignored() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1)
        XCTAssertEqual(viewModel.selectedProductsCount, 0)

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct1)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 1)
        XCTAssertTrue(viewModel.productIsSelected(sampleProduct1))

        // When
        viewModel.deselectProduct(sampleProduct1)
        viewModel.deselectProduct(sampleProduct1)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 0)
        XCTAssertFalse(viewModel.productIsSelected(sampleProduct1))
    }

    func test_bulk_edit_bool_is_set_correctly() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1)
        XCTAssertFalse(viewModel.bulkEditActionIsEnabled)

        // When
        viewModel.selectProduct(sampleProduct1)

        // Then
        XCTAssertTrue(viewModel.bulkEditActionIsEnabled)

        // When
        viewModel.deselectProduct(sampleProduct1)

        // Then
        XCTAssertFalse(viewModel.bulkEditActionIsEnabled)
    }

    func test_deselect_all_works_correctly() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1)
        let sampleProduct2 = Product.fake().copy(productID: 2)

        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)
        XCTAssertEqual(viewModel.selectedProductsCount, 2)

        // When
        viewModel.deselectAll()

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 0)

        // When - Duplicated call
        viewModel.deselectAll()

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 0)
    }

    func test_variation_helpers_work_correctly() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1, productTypeKey: "simple")
        let sampleProduct2 = Product.fake().copy(productID: 2, productTypeKey: "variable")

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 2)
        XCTAssertEqual(viewModel.selectedVariableProductsCount, 1)
        XCTAssertFalse(viewModel.onlyPriceIncompatibleProductsSelected)

        // When
        viewModel.deselectProduct(sampleProduct1)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 1)
        XCTAssertEqual(viewModel.selectedVariableProductsCount, 1)
        XCTAssertTrue(viewModel.onlyPriceIncompatibleProductsSelected)
    }

    func test_product_type_helpers_work_correctly() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)

        // products compatible with bulk price update
        let sampleProduct1 = Product.fake().copy(productID: 1, productTypeKey: "simple")
        let sampleProduct2 = Product.fake().copy(productID: 2, productTypeKey: "affiliate")
        let sampleProduct3 = Product.fake().copy(productID: 3, productTypeKey: "custom-unknown")

        // products incompatible with bulk price update
        let sampleProduct4 = Product.fake().copy(productID: 4, productTypeKey: "variable")
        let sampleProduct5 = Product.fake().copy(productID: 5, productTypeKey: "grouped")
        let sampleProduct6 = Product.fake().copy(productID: 6, productTypeKey: "booking")

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)
        viewModel.selectProduct(sampleProduct3)
        viewModel.selectProduct(sampleProduct4)
        viewModel.selectProduct(sampleProduct5)
        viewModel.selectProduct(sampleProduct6)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 6)
        XCTAssertEqual(viewModel.selectedPriceIncompatibleProductsCount, 3)
        XCTAssertFalse(viewModel.onlyPriceIncompatibleProductsSelected)

        // When
        viewModel.deselectProduct(sampleProduct1)
        viewModel.deselectProduct(sampleProduct2)
        viewModel.deselectProduct(sampleProduct3)

        // Then
        XCTAssertEqual(viewModel.selectedProductsCount, 3)
        XCTAssertEqual(viewModel.selectedPriceIncompatibleProductsCount, 3)
        XCTAssertTrue(viewModel.onlyPriceIncompatibleProductsSelected)
    }

    func test_common_status_works_correctly() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1, statusKey: "draft")
        let sampleProduct2 = Product.fake().copy(productID: 2, statusKey: "draft")
        let sampleProduct3 = Product.fake().copy(productID: 3, statusKey: "publish")
        XCTAssertNil(viewModel.commonStatusForSelectedProducts)

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)

        // Then
        XCTAssertEqual(viewModel.commonStatusForSelectedProducts, .draft)

        // When
        viewModel.selectProduct(sampleProduct3)

        // Then
        XCTAssertNil(viewModel.commonStatusForSelectedProducts)
    }

    func test_common_price_works_correctly() {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1, regularPrice: "100")
        let sampleProduct2 = Product.fake().copy(productID: 2, regularPrice: "100")
        let sampleProduct3 = Product.fake().copy(productID: 3, regularPrice: "200")
        XCTAssertEqual(viewModel.commonPriceForSelectedProducts, .none)

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)

        // Then
        XCTAssertEqual(viewModel.commonPriceForSelectedProducts, .value("100"))

        // When
        viewModel.selectProduct(sampleProduct3)

        // Then
        XCTAssertEqual(viewModel.commonPriceForSelectedProducts, .mixed)
    }

    func test_updating_products_with_status_sets_correct_status() throws {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1, statusKey: "draft")
        let sampleProduct2 = Product.fake().copy(productID: 2, statusKey: "draft")
        let sampleProduct3 = Product.fake().copy(productID: 3, statusKey: "publish")

        storesManager.whenReceivingAction(ofType: ProductAction.self) { action in
            switch action {
            case let .updateProducts(_, products, completion):
                XCTAssertTrue(products.allSatisfy { $0.statusKey == "publish" })
                completion(.success(products))
            default:
                break
            }
        }

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)
        viewModel.selectProduct(sampleProduct3)
        let result = waitFor { promise in
            viewModel.updateSelectedProducts(with: .published) { result in
                promise(result)
            }
        }

        // Then
        XCTAssertTrue(result.isSuccess)
    }

    func test_updating_products_with_price_sets_correct_price_and_filters_simple_products() throws {
        // Given
        let viewModel = ProductListViewModel(siteID: sampleSiteID, stores: storesManager)
        let sampleProduct1 = Product.fake().copy(productID: 1, productTypeKey: "simple", regularPrice: "100")
        let sampleProduct2 = Product.fake().copy(productID: 2, productTypeKey: "affiliate", regularPrice: "200")
        let sampleProduct3 = Product.fake().copy(productID: 3, productTypeKey: "variable", regularPrice: "200")

        storesManager.whenReceivingAction(ofType: ProductAction.self) { action in
            switch action {
            case let .updateProducts(_, products, completion):
                XCTAssertEqual(products.count, 2)
                XCTAssertTrue(products.allSatisfy { $0.regularPrice == "150" })
                completion(.success(products))
            default:
                break
            }
        }

        // When
        viewModel.selectProduct(sampleProduct1)
        viewModel.selectProduct(sampleProduct2)
        viewModel.selectProduct(sampleProduct3)
        let result = waitFor { promise in
            viewModel.updateSelectedProducts(with: "150") { result in
                promise(result)
            }
        }

        // Then
        XCTAssertTrue(result.isSuccess)
    }

    func test_scanToUpdateInventoryButton_when_isScanToUpdateInventoryEnabled_is_true_then_should_be_visible() {
        // Given
        let featureFlagService = MockFeatureFlagService(isScanToUpdateInventoryEnabled: true)
        let viewModel = MockProductListViewModel(featureFlagService: featureFlagService)

        // When
        let result = waitFor { promise in
            viewModel.scanToUpdateInventoryButtonShouldBeVisible { result in
                promise(result)
            }
        }

        // Then
        XCTAssertTrue(result)
    }

    func test_scanToUpdateInventoryButton_when_isScanToUpdateInventoryEnabled_is_false_then_should_not_be_visible() {
        // Given
        let featureFlagService = MockFeatureFlagService(isScanToUpdateInventoryEnabled: false)
        let viewModel = MockProductListViewModel(featureFlagService: featureFlagService)

        // Then
        let result = waitFor { promise in
            viewModel.scanToUpdateInventoryButtonShouldBeVisible { result in
                promise(result)
            }
        }

        // Then
        XCTAssertFalse(result)
    }
}
