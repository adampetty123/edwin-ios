import StoreKit
import SwiftUI

/// Edwin Pro paywall — calm, specific, one clear path.
/// Quarterly is the hero (£14.95 / 3 months, £4.98/mo); monthly is the flexible option.
/// Both start with 7 days free.
struct PaywallView: View {
    @EnvironmentObject var store: Store
    var onClose: (() -> Void)? = nil

    @State private var selected: String = Store.quarterlyId

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 28)

                    Text("Edwin reads the noise.\nYou get your day back.")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(3)
                        .padding(.top, 22)

                    VStack(alignment: .leading, spacing: 16) {
                        pillar(icon: "tray.full.fill", text: "Every chat triaged — only what needs you gets through")
                        pillar(icon: "square.and.pencil", text: "Replies drafted in your voice, sent when you approve")
                        pillar(icon: "calendar.badge.checkmark", text: "Plans land on your calendar the moment they're made")
                        pillar(icon: "envelope.fill", text: "Email and WhatsApp, one assistant across both")
                    }
                    .padding(.top, 24)

                    plans.padding(.top, 28)

                    if let err = store.error {
                        Text(err)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 24)
            }

            footer
        }
        .background(Theme.bg)
        .task { if store.quarterly == nil { await store.loadProducts() } }
    }

    private var header: some View {
        HStack {
            Text("Edwin Pro")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .kerning(1.2)
                .foregroundStyle(Theme.accent)
            Spacer()
            if let onClose {
                Button("Not now") { onClose() }
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func pillar(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15.5, design: .rounded))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var plans: some View {
        VStack(spacing: 10) {
            if let q = store.quarterly {
                planCard(
                    id: Store.quarterlyId,
                    title: "Quarterly",
                    price: "\(store.quarterlyPerMonth ?? "£4.98")/month",
                    detail: "\(q.displayPrice) every 3 months",
                    badge: "Best value"
                )
            }
            if let m = store.monthly {
                planCard(
                    id: Store.monthlyId,
                    title: "Monthly",
                    price: "\(m.displayPrice)/month",
                    detail: "Cancel anytime",
                    badge: nil
                )
            }
            if store.quarterly == nil && store.monthly == nil {
                if store.productsLoaded {
                    Button {
                        Task { store.error = nil; await store.loadProducts() }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Plans didn't load — tap to retry")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
        }
    }

    private func planCard(id: String, title: String, price: String, detail: String, badge: String?) -> some View {
        let isSelected = selected == id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selected = id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.border)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.accent))
                        }
                    }
                    Text(detail)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Text(price)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                guard let product = selected == Store.quarterlyId ? store.quarterly : store.monthly else { return }
                Task {
                    if await store.purchase(product) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onClose?()
                    }
                }
            } label: {
                if store.purchasing {
                    ProgressView().tint(.white)
                } else {
                    Text("Start 7 days free")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.purchasing || (store.quarterly == nil && store.monthly == nil))

            Text(trialLine)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(Theme.textMuted)

            HStack(spacing: 18) {
                Button("Restore purchases") { Task { await store.restore() } }
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy", destination: URL(string: "https://iris-app.expo.app/privacy")!)
            }
            .font(.system(size: 12.5, design: .rounded))
            .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Theme.bg)
    }

    private var trialLine: String {
        if selected == Store.quarterlyId, let q = store.quarterly {
            return "7 days free, then \(q.displayPrice) every 3 months. Cancel anytime."
        }
        if let m = store.monthly {
            return "7 days free, then \(m.displayPrice) a month. Cancel anytime."
        }
        return "7 days free. Cancel anytime."
    }
}
