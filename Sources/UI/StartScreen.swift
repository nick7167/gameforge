import SwiftUI

/// Monument Minimalism menu: sandstone gradient, serif title, level + Coins.
struct StartScreen: View {
    let level: Int
    let coins: Int
    let onStart: () -> Void
    let onShop: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("Skyline Stack")
                .font(.system(size: 44, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 0.35, green: 0.22, blue: 0.12))
            Text("Build your city skyward")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onStart) {
                Text("Build")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            Button(action: onShop) {
                Label("Shop", systemImage: "bag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 40)
            HStack(spacing: 24) {
                Label("Level \(level)", systemImage: "star")
                Label("\(coins)", systemImage: "circlebadge.fill")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.90, blue: 0.78), Color(red: 0.88, green: 0.76, blue: 0.60)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

#Preview {
    StartScreen(level: 1, coins: 0, onStart: {}, onShop: {})
}
