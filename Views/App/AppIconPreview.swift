import SwiftUI

/// Preview لتصميم أيقونة التطبيق - شغّلها في Preview وخذ screenshot
/// الحجم: 1024x1024 للـ App Store
struct AppIconPreview: View {
    var body: some View {
        ZStack {
            // خلفية ملكية — أزرق غامق فخم
            LinearGradient(
                colors: [
                    Color(hex: "0A1628"),   // كحلي غامق جداً
                    Color(hex: "0E2460"),   // أزرق ملكي غامق
                    Color(hex: "1B3A8C"),   // أزرق ملكي
                    Color(hex: "0D1B40"),   // كحلي للزوايا
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // دوائر ديكورية بتوهج ذهبي
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "C8962E").opacity(0.15), .clear],
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
                        colors: [Color(hex: "E6C06A").opacity(0.10), .clear],
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
                        colors: [Color(hex: "C8962E").opacity(0.08), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: 250, y: -200)

            // حلقة خارجية ذهبية
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: "E6C06A").opacity(0.25),
                            Color(hex: "C8962E").opacity(0.12),
                            Color(hex: "E6C06A").opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 820, height: 820)

            // المحتوى الرئيسي
            VStack(spacing: 0) {
                // أيقونة العائلة مع توهج
                ZStack {
                    // توهج خلفي
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

                    // دائرة زجاجية
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

                    // أيقونة الشجرة
                    Image(systemName: "tree.fill")
                        .font(DS.Font.scaled(200, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FDFBF7"), Color(hex: "E6C06A")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color(hex: "C8962E").opacity(0.5), radius: 30, y: 8)
                        .shadow(color: .black.opacity(0.15), radius: 15, y: 10)
                }
                .offset(y: -40)

                // اسم العائلة
                VStack(spacing: 8) {
                    Text("عائلة")
                        .font(.system(size: 48, weight: .bold, design: .serif))
                        .foregroundStyle(.white.opacity(0.85))

                    Text("المحمدعلي")
                        .font(.system(size: 110, weight: .heavy, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FDFBF7"), Color(hex: "C8962E")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(hex: "9A7321").opacity(0.6), radius: 20, y: 4)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)

                    // خط فاصل مزخرف
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color(hex: "C8962E").opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 120, height: 2.5)

                        Circle()
                            .fill(Color(hex: "E6C06A"))
                            .frame(width: 8, height: 8)

                        Text("شجرة العائلة")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(Color(hex: "E6C06A").opacity(0.85))

                        Circle()
                            .fill(Color(hex: "E6C06A"))
                            .frame(width: 8, height: 8)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "C8962E").opacity(0.8), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 120, height: 2.5)
                    }
                }
                .offset(y: -10)
            }

            // نجوم صغيرة ديكورية
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
        .clipShape(RoundedRectangle(cornerRadius: 224))
    }
}

/// تصميم بديل — أزرق ملكي مع ذهبي
struct AppIconPreviewAlt: View {
    var body: some View {
        ZStack {
            // خلفية ملكية متدرجة
            LinearGradient(
                colors: [
                    Color(hex: "0A1628"),
                    Color(hex: "1B3A8C"),
                    Color(hex: "0E2460"),
                    Color(hex: "162D6B"),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // توهج ذهبي مركزي
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "C8962E").opacity(0.30), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 400
                    )
                )
                .frame(width: 800, height: 800)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "E6C06A").opacity(0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: 200, y: -250)

            // حلقات دائرية
            Circle()
                .stroke(.white.opacity(0.06), lineWidth: 1.5)
                .frame(width: 700, height: 700)

            Circle()
                .stroke(.white.opacity(0.04), lineWidth: 1)
                .frame(width: 850, height: 850)

            // المحتوى
            VStack(spacing: 30) {
                // أيقونة العائلة
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.15), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 220
                            )
                        )
                        .frame(width: 440, height: 440)

                    Image(systemName: "figure.2.and.child.holdinghands")
                        .font(DS.Font.scaled(220, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: Color(hex: "C8962E").opacity(0.6), radius: 40, y: 10)
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 12)
                }

                // اسم العائلة
                Text("المحمدعلي")
                    .font(.system(size: 140, weight: .black, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(hex: "E6C06A")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Color(hex: "C8962E").opacity(0.5), radius: 25, y: 5)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 8)
            }
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 224))
    }
}

/// تصميم ثالث — حرف م مع أزرق ملكي وذهبي
struct AppIconPreviewMinimal: View {
    var body: some View {
        ZStack {
            // خلفية ملكية
            LinearGradient(
                colors: [
                    Color(hex: "0A1628"),
                    Color(hex: "1B3A8C"),
                    Color(hex: "162D6B"),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // توهج مركزي ذهبي
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "C8962E").opacity(0.25), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 350
                    )
                )
                .frame(width: 700, height: 700)

            // حلقة ذهبية gradient
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: "E6C06A").opacity(0.4),
                            Color(hex: "C8962E").opacity(0.2),
                            Color(hex: "E6C06A").opacity(0.3),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 5
                )
                .frame(width: 680, height: 680)

            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 580, height: 580)

            // حرف م كبير
            VStack(spacing: 20) {
                Text("م")
                    .font(.system(size: 480, weight: .black, design: .serif))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(hex: "E6C06A").opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(hex: "C8962E").opacity(0.6), radius: 30, y: 8)
                    .shadow(color: .black.opacity(0.2), radius: 15, y: 10)

                // أيقونة عائلة صغيرة تحت الحرف
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(DS.Font.scaled(60, weight: .bold))
                    .foregroundStyle(Color(hex: "E6C06A").opacity(0.5))
            }
            .offset(y: -30)
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 224))
    }
}

#Preview("App Icon - Family Bold", traits: .fixedLayout(width: 1024, height: 1024)) {
    AppIconPreview()
}

#Preview("App Icon - Dark Bold", traits: .fixedLayout(width: 1024, height: 1024)) {
    AppIconPreviewAlt()
}

#Preview("App Icon - م Minimal", traits: .fixedLayout(width: 1024, height: 1024)) {
    AppIconPreviewMinimal()
}
