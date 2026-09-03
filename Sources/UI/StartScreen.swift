import SwiftUI

/// Monument Minimalism menu: layered skyline hero, single dominant CTA in
/// the thumb zone, quiet status row. Follows mobile-app-ui-design skill:
/// one family, 3 sizes, 60/30/10 color, 8-pt grid, peak-end framing.
struct StartScreen: View {
    let level: Int
    let coins: Int
    var bestHeight: Int = 0
    let onStart: () -> Void
    let onShop: () -> Void

    // 60% sand neutrals / 30% deep brown ink / 10% terracotta accent.
    private let sandTop = Color(red: 0.98, green: 0.94, blue: 0.86)
    private let sandBottom = Color(red: 0.92, green: 0.82, blue: 0.66)
    private let ink = Color(red: 0.29, green: 0.20, blue: 0.12)
    private let accent = Color(red: 0.80, green: 0.44, blue: 0.26)

    var body: some View {
        ZStack {
            LinearGradient(colors: [sandTop, sandBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Status row — quiet, top.
                HStack(spacing: 16) {
                    Label("LV \(level)", systemImage: "star.fill")
                    Spacer()
                    Label("\(coins)", systemImage: "circlebadge.fill")
                }
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(ink.opacity(0.65))
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer(minLength: 32)

                // Hero: layered skyline silhouette built from simple shapes.
                SkylineHero()
                    .frame(height: 260)
                    .padding(.horizontal, 32)

                Spacer(minLength: 24)

                // Title block.
                VStack(spacing: 8) {
                    Text("Skyline Stack")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .foregroundStyle(ink)
                    Text(bestHeight > 0
                         ? "Best: \(bestHeight) m — beat it."
                         : "Stack a city into the clouds.")
                        .font(.body)
                        .foregroundStyle(ink.opacity(0.7))
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 48)

                // Primary CTA — thumb zone, one dominant action.
                Button(action: onStart) {
                    Text("Build")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(accent)
                                .shadow(color: accent.opacity(0.4), radius: 12, y: 6)
                        )
                }
                .padding(.horizontal, 32)
                .accessibilityIdentifier("start-build-button")

                // Secondary — quiet text button, not a competing block.
                Button(action: onShop) {
                    Label("Shop", systemImage: "bag")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.6))
                        .padding(.vertical, 16)
                }
                .padding(.bottom, 24)
            }
        }
    }
}

/// Layered building silhouettes with a sun disc — pure shapes, no assets.
private struct SkylineHero: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(Color(red: 0.99, green: 0.80, blue: 0.55))
                .frame(width: 96, height: 96)
                .blur(radius: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 28)
                .padding(.bottom, 96)

            HStack(alignment: .bottom, spacing: 10) {
                BuildingShape(width: 44, height: 90, color: .init(red: 0.87, green: 0.74, blue: 0.58))
                BuildingShape(width: 34, height: 130, color: .init(red: 0.84, green: 0.69, blue: 0.52))
                BuildingShape(width: 52, height: 70, color: .init(red: 0.88, green: 0.77, blue: 0.62))
                BuildingShape(width: 38, height: 110, color: .init(red: 0.85, green: 0.71, blue: 0.55))
                BuildingShape(width: 46, height: 84, color: .init(red: 0.87, green: 0.75, blue: 0.60))
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .bottom, spacing: 12) {
                BuildingShape(width: 56, height: 64, color: .init(red: 0.62, green: 0.42, blue: 0.28))
                BuildingShape(width: 44, height: 100, color: .init(red: 0.55, green: 0.36, blue: 0.24))
                BuildingShape(width: 64, height: 52, color: .init(red: 0.66, green: 0.46, blue: 0.31))
                BuildingShape(width: 48, height: 84, color: .init(red: 0.58, green: 0.39, blue: 0.26))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct BuildingShape: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: width, height: height)
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    ForEach(0..<max(1, Int(height / 28)), id: \.self) { _ in
                        HStack(spacing: 6) {
                            ForEach(0..<max(1, Int(width / 20)), id: \.self) { _ in
                                Circle()
                                    .fill(Color.white.opacity(0.35))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
    }
}

#Preview {
    StartScreen(level: 3, coins: 240, bestHeight: 120, onStart: {}, onShop: {})
}
