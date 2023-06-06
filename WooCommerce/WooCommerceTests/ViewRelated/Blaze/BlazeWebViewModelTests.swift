import XCTest
import Yosemite
@testable import WooCommerce

final class BlazeWebViewModelTests: XCTestCase {
    // MARK: - `initialURL`

    func test_initialURL_includes_source_and_siteURL_and_productID_when_product_is_available() {
        // Given
        let source: BlazeSource = .menu
        let site = Site.fake().copy(url: "https://example.com")
        let productID: Int64? = 134
        let viewModel = BlazeWebViewModel(source: source, site: site, productID: productID)

        // Then
        XCTAssertEqual(viewModel.initialURL, URL(string: "https://wordpress.com/advertising/example.com?blazepress-widget=post-134&source=menu"))
    }

    func test_initialURL_includes_source_and_siteURL_when_product_is_unavailable() {
        // Given
        let source: BlazeSource = .productMoreMenu
        let site = Site.fake().copy(url: "https://example.com")
        let viewModel = BlazeWebViewModel(source: source, site: site, productID: nil)

        // Then
        XCTAssertEqual(viewModel.initialURL, URL(string: "https://wordpress.com/advertising/example.com?source=product_more_menu"))
    }
}
