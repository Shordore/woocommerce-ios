import UIKit

class BasicTableViewCell: UITableViewCell {

    override func awakeFromNib() {
        super.awakeFromNib()

        configureBackground()
        textLabel?.applyBodyStyle()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        textLabel?.applyBodyStyle()
        textLabel?.textAlignment = .natural
        accessibilityIdentifier = nil
    }
}


private extension BasicTableViewCell {
    func configureBackground() {
        applyDefaultBackgroundStyle()
        applyDefaultSelectedBackgroundStyle()
    }
}
