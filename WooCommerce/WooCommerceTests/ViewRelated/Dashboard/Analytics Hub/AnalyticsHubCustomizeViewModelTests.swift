import XCTest
@testable import WooCommerce
import Yosemite

final class AnalyticsHubCustomizeViewModelTests: XCTestCase {

    func test_it_inits_with_expected_properties() {
        // Given
        let revenueCard = AnalyticsCard(type: .revenue, enabled: true, sortOrder: 0)
        let ordersCard = AnalyticsCard(type: .orders, enabled: false, sortOrder: 1)
        let vm = AnalyticsHubCustomizeViewModel(allCards: [revenueCard, ordersCard])

        // Then
        assertEqual([revenueCard, ordersCard], vm.allCards)
        assertEqual([revenueCard], vm.selectedCards)
        XCTAssertFalse(vm.hasChanges)
    }

    func test_it_groups_all_selected_cards_at_top_of_allCards_list_in_original_order() {
        // Given
        let revenueCard = AnalyticsCard(type: .revenue, enabled: false, sortOrder: 0)
        let ordersCard = AnalyticsCard(type: .orders, enabled: true, sortOrder: 1)
        let productsCard = AnalyticsCard(type: .products, enabled: true, sortOrder: 2)
        let vm = AnalyticsHubCustomizeViewModel(allCards: [revenueCard, ordersCard, productsCard])

        // Then
        assertEqual([ordersCard, productsCard, revenueCard], vm.allCards)
    }

    func test_hasChanges_is_true_when_card_order_changes() {
        // Given
        let revenueCard = AnalyticsCard(type: .revenue, enabled: false, sortOrder: 0)
        let ordersCard = AnalyticsCard(type: .orders, enabled: false, sortOrder: 1)
        let vm = AnalyticsHubCustomizeViewModel(allCards: [revenueCard, ordersCard])

        // When
        vm.allCards = [ordersCard, revenueCard]

        // Then
        XCTAssertTrue(vm.hasChanges)
    }

    func test_hasChanges_is_true_when_selection_changes() {
        // Given
        let revenueCard = AnalyticsCard(type: .revenue, enabled: false, sortOrder: 0)
        let ordersCard = AnalyticsCard(type: .orders, enabled: true, sortOrder: 1)
        let vm = AnalyticsHubCustomizeViewModel(allCards: [revenueCard, ordersCard])

        // When
        vm.selectedCards = [revenueCard, ordersCard]

        // Then
        XCTAssertTrue(vm.hasChanges)
    }

}
