import UIKit

/// Displays a  button to issue new refunds.
///
final class IssueRefundTableViewCell: UITableViewCell {
    @IBOutlet private var issueRefundButton: UIButton!

    var onIssueRefundTouchUp: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()

        configureBackground()
        configureIssueRefundButton()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        updateDefaultBackgroundConfiguration(using: state)
    }
}

// MARK: Actions
extension IssueRefundTableViewCell {
    @IBAction func issueRefundWasPressed() {
        onIssueRefundTouchUp?()
    }
}

// MARK: View Configuration
private extension IssueRefundTableViewCell {
    func configureBackground() {
        configureDefaultBackgroundConfiguration()
    }

    func configureIssueRefundButton() {
        issueRefundButton.applySecondaryButtonStyle()
        issueRefundButton.setTitle(Localization.buttonTitle, for: .normal)
    }
}

// MARK: Localization
private extension IssueRefundTableViewCell {
    enum Localization {
        static let buttonTitle = NSLocalizedString("Issue Refund", comment: "Text on the button that starts a new refund process")
    }
}
