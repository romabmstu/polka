import PolkaCore
import PolkaSystem
import SwiftUI

struct CalculatorSection: View {
    var body: some View {
        HStack(spacing: 12) {
            CalculatorCard()
            ConverterCard()
        }
    }
}

private struct CalculatorCard: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var calculator = app.calculator
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel("Calculator")
                TextField("1250 × 1.2 + 15%", text: $calculator.expression)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12, style: .continuous))
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in app.panel.isEditingText = focused }
                    .onAppear { isFocused = true }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    Text("=").font(.system(size: 22)).foregroundStyle(Theme.tertiary)
                    Spacer()
                    Text(calculator.formattedResult ?? "—")
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .textSelection(.enabled)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: calculator.formattedResult)
                }
                HStack {
                    Text("+ − × ÷ ^ % and brackets")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    if let result = calculator.formattedResult {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result, forType: .string)
                            app.panel.flash(.init(symbol: "doc.on.doc", text: String(localized: "Copied \(result)")))
                        }
                        .buttonStyle(CapsuleButtonStyle())
                    }
                }
            }
        }
    }
}

private struct ConverterCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var calculator = app.calculator
        let favorites = app.preferences.favoriteCurrencies
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel("Currency")
                    Spacer()
                    if app.preferences.exchangeRatesEnabled {
                        if calculator.isRefreshing {
                            ProgressView().controlSize(.mini)
                        } else if let rates = calculator.rates {
                            Text(rates.fetchedAt, format: .relative(presentation: .named))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                }

                if !app.preferences.exchangeRatesEnabled {
                    optIn
                } else {
                    HStack(spacing: 8) {
                        TextField("100", text: $calculator.amountText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .medium).monospacedDigit())
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12, style: .continuous))
                        Picker("Currency", selection: $calculator.baseCurrency) {
                            ForEach(favorites, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    VStack(spacing: 0) {
                        ForEach(favorites.filter { $0 != calculator.baseCurrency }, id: \.self) { code in
                            HStack {
                                Text(Locale.current.localizedString(forCurrencyCode: code) ?? code)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(formatted(calculator.converted(to: code), code: code))
                                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                                    .textSelection(.enabled)
                            }
                            .frame(height: 34)
                            Divider().overlay(Theme.hairline)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack {
                        if let error = calculator.ratesError {
                            Text(error).foregroundStyle(Theme.warning)
                        } else {
                            Link("Rates by ExchangeRate-API", destination: RatesClient.attributionURL)
                                .foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        Button {
                            Task { await calculator.refreshRates() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(IconButtonStyle(size: 24))
                        .help(Text("Update rates"))
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }

    private var optIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text("Convert between your currencies")
                .font(.system(size: 15, weight: .semibold))
            Text("Rates are downloaded from open.er-api.com a few times a day. No personal data is sent; this is the only thing Polka uses the network for.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn On") {
                app.preferences.exchangeRatesEnabled = true
                Task { await app.calculator.refreshRatesIfNeeded(enabled: true) }
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            Spacer(minLength: 0)
        }
    }

    private func formatted(_ value: Decimal?, code: String) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: code).precision(.fractionLength(value < 100 ? 2 : 0)))
    }
}
