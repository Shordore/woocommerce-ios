import SwiftUI
import Yosemite

@available(iOS 16.0, *)
struct WooPaymentsDepositsOverviewView: View {
    let viewModels: [WooPaymentsDepositsCurrencyOverviewViewModel]

    var tabs: [TopTabItem] {
        viewModels.map { tabViewModel in
            TopTabItem(name: tabViewModel.overview.currency.rawValue,
                       view: AnyView(WooPaymentsDepositsCurrencyOverviewView(viewModel: tabViewModel)))
        }
    }

    var body: some View {
        VStack {
            TopTabView(tabs: tabs)
            Button {
                // no-op
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Learn more about when you'll receive your funds")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

@available(iOS 16.0, *)
struct WooPaymentsDepositsOverviewView_Previews: PreviewProvider {
    static var previews: some View {
        let overviewData = WooPaymentsDepositsOverviewByCurrency(
            currency: .GBP,
            automaticDeposits: true,
            depositInterval: .daily,
            pendingBalanceAmount: 1000.0,
            pendingDepositsCount: 5,
            nextDeposit: WooPaymentsDepositsOverviewByCurrency.NextDeposit(
                amount: 250.0,
                date: Date(),
                status: .pending
            ),
            lastDeposit: WooPaymentsDepositsOverviewByCurrency.LastDeposit(
                amount: 500.0,
                date: Date()
            ),
            availableBalance: 1500.0
        )

        let viewModel1 = WooPaymentsDepositsCurrencyOverviewViewModel(overview: overviewData)

        let overviewData2 = WooPaymentsDepositsOverviewByCurrency(
            currency: .EUR,
            automaticDeposits: true,
            depositInterval: .daily,
            pendingBalanceAmount: 200.0,
            pendingDepositsCount: 5,
            nextDeposit: WooPaymentsDepositsOverviewByCurrency.NextDeposit(
                amount: 190.0,
                date: Date(),
                status: .pending
            ),
            lastDeposit: WooPaymentsDepositsOverviewByCurrency.LastDeposit(
                amount: 600.0,
                date: Date()
            ),
            availableBalance: 1900.0
        )

        let viewModel2 = WooPaymentsDepositsCurrencyOverviewViewModel(overview: overviewData2)

        WooPaymentsDepositsOverviewView(viewModels: [viewModel1, viewModel2])
    }
}
