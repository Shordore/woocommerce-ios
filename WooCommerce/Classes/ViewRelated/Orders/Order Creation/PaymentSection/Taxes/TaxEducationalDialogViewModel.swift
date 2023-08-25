import Yosemite
import WooFoundation

struct TaxEducationalDialogViewModel {
    struct TaxLine {
        let title: String
        let value: String
    }

    let taxLines: [TaxLine]
    let taxBasedOnSettingExplanatoryText: String?

    init(orderTaxLines: [OrderTaxLine], taxBasedOnSetting: TaxBasedOnSetting?) {
        self.taxLines = orderTaxLines.map { TaxLine(title: $0.label, value: $0.ratePercent.percentFormatted() ?? "") }
        self.taxBasedOnSettingExplanatoryText = taxBasedOnSetting?.explanatoryText
    }
}

private extension TaxBasedOnSetting {
    var explanatoryText: String {
        switch self {
        case .customerBillingAddress:
            return NSLocalizedString("Your tax rate is currently calculated based on the customer billing address:",
                                     comment: "Educational tax dialog to explain that the rate is calculated based on the customer billing address.")
        case .customerShippingAddress:
            return NSLocalizedString("Your tax rate is currently calculated based on the customer shipping address:",
                                     comment: "Educational tax dialog to explain that the rate is calculated based on the customer shipping address.")
        case .shopBaseAddress:
            return NSLocalizedString("Your tax rate is currently calculated based on your shop address:",
                                     comment: "Educational tax dialog to explain that the rate is calculated based on the shop address.")
        }
    }
}
