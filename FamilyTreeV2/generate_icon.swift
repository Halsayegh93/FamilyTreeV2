import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct AppIconPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "0D1A14"),   // أخضر غابي غامق جداً
                    Color(hex: "183125"),   // أخضر غابي
                    Color(hex: "213B2E"),   // أخضر غابي أفتح قليلاً
                    Color(hex: "13241A"),   // أخضر داكن للزوايا
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "C8A165").opacity(0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 350
                    )
                )
                .frame(width: 700, height: 700)
                .offset(x: -250, y: -300)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "D4AF37").opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(x: 300, y: 350)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "E2CA9E").opacity(0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: 250, y: -200)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: "E2CA9E").opacity(0.2),
                            Color(hex: "C8A165").opacity(0.10),
                            Color(hex: "E2CA9E").opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 820, height: 820)

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.18), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 260
                            )
                        )
                        .frame(width: 520, height: 520)

                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 420, height: 420)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )

                    Image(systemName: "tree.fill")
                        .font(.system(size: 200, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FDFBF7"), Color(hex: "E2CA9E")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(hex: "C8A165").opacity(0.5), radius: 30, y: 8)
                        .shadow(color: .black.opacity(0.15), radius: 15, y: 10)
                }
                .offset(y: -40)

                VStack(spacing: 8) {
                    Text("عائلة")
                        .font(.system(size: 48, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))
                        
                    Text("المحمدعلي")
                        .font(.system(size: 110, weight: .heavy, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FDFBF7"), Color(hex: "D4AF37")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(hex: "9C7A4A").opacity(0.6), radius: 20, y: 4)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)

                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color(hex: "C8A165").opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 120, height: 2.5)

                        Circle()
                            .fill(Color(hex: "D4AF37"))
                            .frame(width: 8, height: 8)

                        Text("شجرة العائلة")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(Color(hex: "E2CA9E").opacity(0.85))

                        Circle()
                            .fill(Color(hex: "D4AF37"))
                            .frame(width: 8, height: 8)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "C8A165").opacity(0.8), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 120, height: 2.5)
                    }
                }
                .offset(y: -10)
            }

            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(Double.random(in: 0.15...0.45)))
                    .frame(width: CGFloat.random(in: 4...10), height: CGFloat.random(in: 4...10))
                    .offset(
                        x: CGFloat([-380, 350, -300, 400, -420, 280, -200, 380][i]),
                        y: CGFloat([-350, -280, 380, 300, 100, -400, -420, 180][i])
                    )
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
struct IconGenerator {
    @MainActor
    static func main() {
        let renderer = ImageRenderer(content: AppIconPreview())
        renderer.scale = 1.0
        if let cgImage = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "AppIcon.png"))
                print("Success")
            } else {
                print("Failed to get PNG data")
            }
        } else {
            print("Failed to get CGImage")
        }
    }
}
