import SwiftUI

/// Preview لتصميم أيقونة التطبيق - شغّلها في Preview وخذ screenshot
/// الحجم: 1024x1024 للـ App Store
struct AppIconPreview: View {
    // ألوان التصميم — Ocean Blue
    private let oceanBlue = Color(hex: "2B7A9F")
    private let oceanDark = Color(hex: "1E5474")
    private let oceanLight = Color(hex: "78ACC3")
    private let cyanSoft = Color(hex: "A3C4D3")

    var body: some View {
        ZStack {
            // خلفية Ocean Blue متدرجة
            LinearGradient(
                colors: [
                    Color(hex: "0A2A3C"),
                    Color(hex: "0F3650"),
                    Color(hex: "164560"),
                    Color(hex: "0D2E42"),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // توهج أزرق مركزي علوي (خلف الشجرة)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [oceanBlue.opacity(0.25), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 380
                    )
                )
                .frame(width: 760, height: 760)
                .offset(y: -80)

            // توهج سماوي خفيف
            Circle()
                .fill(
                    RadialGradient(
                        colors: [cyanSoft.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: -150, y: -200)

            // حلقة دائرية خارجية رفيعة
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [oceanLight.opacity(0.12), oceanBlue.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 860, height: 860)

            // === رمز الشجرة الكبير ===
            ZStack {
                // توهج خلفي للشجرة
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [oceanLight.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 300
                        )
                    )
                    .frame(width: 600, height: 600)

                // أيقونة الشجرة
                Image(systemName: "tree.fill")
                    .font(.system(size: 420, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                .white,
                                oceanLight,
                                oceanBlue,
                                oceanDark,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: oceanBlue.opacity(0.6), radius: 40, y: 10)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 15)
            }
            .offset(y: -30)

            // اسم العائلة تحت الشجرة
            Text("المحمدعلي")
                .font(.system(size: 110, weight: .heavy, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, oceanLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: oceanBlue.opacity(0.5), radius: 20, y: 4)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                .offset(y: 360)

            // نقاط ديكورية صغيرة حول الشجرة
            ForEach(0..<8, id: \.self) { i in
                let positions: [(x: CGFloat, y: CGFloat)] = [
                    (-320, -300), (320, -280), (-380, 50), (380, 80),
                    (-280, 300), (300, 320), (-150, -380), (180, 380)
                ]
                let sizes: [CGFloat] = [6, 5, 8, 5, 7, 6, 4, 5]
                let opacities: [Double] = [0.4, 0.25, 0.35, 0.2, 0.3, 0.25, 0.45, 0.2]

                Circle()
                    .fill(oceanLight.opacity(opacities[i]))
                    .frame(width: sizes[i], height: sizes[i])
                    .offset(x: positions[i].x, y: positions[i].y)
            }
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 224))
    }
}

/// شكل سداسي منتظم
struct RegularPolygon: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for i in 0..<sides {
            let angle = (Double(i) / Double(sides)) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
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
