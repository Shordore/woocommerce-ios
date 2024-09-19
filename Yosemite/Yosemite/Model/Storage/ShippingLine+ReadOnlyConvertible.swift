import Foundation
import Storage


// MARK: - Storage.ShippingLine: ReadOnlyConvertible
//
extension Storage.ShippingLine: ReadOnlyConvertible {

    /// Updates the Storage.ShippingLine with the ReadOnly.
    ///
    public func update(with shippingLine: Yosemite.ShippingLine) {
        shippingID = shippingLine.shippingID
        methodTitle = shippingLine.methodTitle
        methodID = shippingLine.methodID
        total = shippingLine.total
        totalTax = shippingLine.totalTax
    }

    /// Returns a ReadOnly version of the receiver.
    ///
    public func toReadOnly() -> Yosemite.ShippingLine {
        let lineTaxes = taxes?.map { $0.toReadOnly() } ?? []
        return ShippingLine(shippingID: shippingID,
                            methodTitle: methodTitle ?? "",
                            methodID: methodID ?? "",
                            total: total ?? "",
                            totalTax: totalTax ?? "",
                            taxes: lineTaxes)
    }
}
