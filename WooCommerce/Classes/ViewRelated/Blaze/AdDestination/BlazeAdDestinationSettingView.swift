import SwiftUI

/// View to set ad destination for a new Blaze campaign
struct BlazeAdDestinationSettingView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var viewModel: BlazeAdDestinationSettingViewModel

    typealias DestinationType = BlazeAdDestinationSettingViewModel.DestinationURLType

    @State private var isShowingAddParameterView = false

    init(viewModel: BlazeAdDestinationSettingViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    destinationItem(title: Localization.productURLLabel,
                                    subtitle: String(format: Localization.destinationUrlSubtitle, viewModel.productURL),
                                    type: DestinationType.product)
                    .listRowInsets(EdgeInsets())

                    destinationItem(title: Localization.siteHomeLabel,
                                    subtitle: String(format: Localization.destinationUrlSubtitle, viewModel.homeURL),
                                    type: DestinationType.home)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text(Localization.destinationUrlHeading)
                }


                Section {
                    ForEach(viewModel.parameters, id: \.id) { parameter in
                        parameterItem(parameter: parameter)
                    }
                    .onDelete(perform: deleteParameter)

                    Button(action: {
                        isShowingAddParameterView = true
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text(Localization.addParameterButton)
                        }
                    }
                    .foregroundColor(Color(uiColor: .accent))
                    .listRowInsets(EdgeInsets())
                    .padding(.top, 0)
                    .padding(.leading, Layout.contentSpacing)
                    .listRowSeparator(.hidden, edges: .bottom)
                    .disabled(viewModel.calculateRemainingCharacters() == 0)

                } header: {
                    Text(Localization.urlParametersHeading)
                } footer: {
                    // Remaining characters and final destination
                    VStack(alignment: .leading) {
                        Text(viewModel.remainingCharactersLabel)
                            .foregroundColor(Color(uiColor: .secondaryLabel))
                            .captionStyle()
                            .padding(.bottom, Layout.footerVerticalSpacing)

                        Text(viewModel.finalDestinationLabel)
                            .foregroundColor(Color(uiColor: .secondaryLabel))
                            .captionStyle()
                    }
                    .padding(.vertical, Layout.contentVerticalSpacing)
                }
            }
            .listStyle(.grouped)
            .background(Color(.listBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(Localization.adDestination)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localization.cancel) {
                        dismiss()
                    }
                    .foregroundColor(Color(uiColor: .accent))
                }
            }
            .sheet(isPresented: $isShowingAddParameterView) {
                BlazeAddParameterView(viewModel: viewModel.blazeAddParameterViewModel)
            }
        }
    }
    private func sectionHeading(title: String) -> some View {
        Text(title.uppercased())
            .subheadlineStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.sectionHeadingPadding)
    }

    private func destinationItem(title: String,
                                 subtitle: String,
                                 type: DestinationType) -> some View {
        HStack(alignment: .center) {
            Image(systemName: "checkmark")
                .padding(.leading, Layout.contentSpacing)
                .padding(.trailing, Layout.contentHorizontalSpacing)
                .foregroundColor(Color(uiColor: .accent))
                .if(type != viewModel.selectedDestinationType) { view in
                    view.hidden()
                }

            VStack(alignment: .leading) {
                Text(title)
                    .bodyStyle()
                    .padding(.top, Layout.contentVerticalSpacing)
                Text(subtitle)
                    .foregroundColor(Color(uiColor: .secondaryLabel))
                    .captionStyle()
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, Layout.contentVerticalSpacing)
            }
        }
        .onTapGesture {
            viewModel.setDestinationType(as: type)
        }
    }

    private func parameterItem(parameter: BlazeAdURLParameter) -> some View {
        Button(action: {
            viewModel.selectParameter(item: parameter)
            isShowingAddParameterView = true
        }) {
            HStack {
                Text(parameter.key)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .padding(.leading, Layout.contentHorizontalSpacing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deleteParameter(at offsets: IndexSet) {
        viewModel.deleteParameter(at: offsets)
    }
}

private extension BlazeAdDestinationSettingView {
    enum Layout {
        static let verticalSpacing: CGFloat = 16
        static let contentSpacing: CGFloat = 16
        static let footerVerticalSpacing: CGFloat =  10
        static let contentVerticalSpacing: CGFloat = 8
        static let contentHorizontalSpacing: CGFloat = 8
        static let sectionVerticalSpacing: CGFloat = 24
        static let parametersVerticalSpacing: CGFloat = 11
        static let sectionHeadingPadding: EdgeInsets = .init(top: 16, leading: 16, bottom: 8, trailing: 16)
    }

    enum Localization {
        static let cancel = NSLocalizedString(
            "blazeAdDestinationSettingView.cancel",
            value: "Cancel",
            comment: "Button to dismiss the Blaze Ad Destination setting screen"
        )
        static let adDestination = NSLocalizedString(
            "blazeAdDestinationSettingView.adDestination",
            value: "Ad Destination",
            comment: "Title of the Blaze Ad Destination setting screen."
        )

        static let destinationUrlHeading = NSLocalizedString(
            "blazeAdDestinationSettingView.destinationUrlHeading",
            value: "Destination URL",
            comment: "Heading for the destination URL section in Blaze Ad Destination screen.")

        static let productURLLabel = NSLocalizedString(
            "blazeAdDestinationSettingView.productURLLabel",
            value: "The Product URL",
            comment: "Label for the product URL destination option in Blaze Ad Destination screen."
        )

        static let siteHomeLabel = NSLocalizedString(
            "blazeAdDestinationSettingView.siteHomeLabel",
            value: "The site home",
            comment: "Label for the site home destination option in Blaze Ad Destination screen."
        )


        static let destinationUrlSubtitle = NSLocalizedString(
            "blazeAdDestinationSettingView.destinationUrlSubtitle",
            value: "It will link to: %1$@",
            comment: "Subtitle for each destination type showing the URL to link to. " +
            "%1$@ will be replaced by the URL."
        )

        static let urlParametersHeading = NSLocalizedString(
            "blazeAdDestinationSettingView.urlParametersHeading",
            value: "URL Parameters",
            comment: "Heading for the URL Parameters section in Blaze Ad Destination screen."
        )

        static let addParameterButton = NSLocalizedString(
            "blazeAdDestinationSettingView.addParameterButton",
            value: "Add parameter",
            comment: "Button to add a new URL parameter in Blaze Ad Destination screen."
        )
    }
}

struct BlazeAdDestinationSettingView_Previews: PreviewProvider {
    static var previews: some View {
        BlazeAdDestinationSettingView(
            viewModel: .init(
                productURL: "https://woo.com/product",
                homeURL: "https://woo.com/",
                parameters: [
                    BlazeAdURLParameter(key: "key1", value: "value1"),
                    BlazeAdURLParameter(key: "key2", value: "value2"),
                    BlazeAdURLParameter(key: "key1", value: "value1")
                ]
            )
        )
    }
}
