import SwiftUI

struct ImageCropperView: View {
    let image: UIImage
    let cropShape: CropShape
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    enum CropShape {
        case circle
        case square
    }

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var displayImage: UIImage?

    private let maxDisplaySize: CGFloat = 1200

    @State private var containerSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let screenW = max(geometry.size.width, 1)
            let screenH = max(geometry.size.height, 1)
            let cropSize = max(min(screenW - 40, screenH * 0.55), 44)

            ZStack {
                // خلفية شفافة مع blur
                Color(uiColor: .systemBackground).ignoresSafeArea()
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                ZStack {
                    // Image layer
                    if let img = displayImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cropSize * 1.5, height: cropSize * 1.5)
                            .clipped()
                            .scaleEffect(scale)
                            .offset(offset)
                    } else {
                        ProgressView().tint(.white)
                    }

                    // Static overlay mask
                    cropOverlay(cropSize: cropSize, screenW: screenW, screenH: screenH)
                        .allowsHitTesting(false)
                }
                .frame(width: screenW, height: screenH)
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .gesture(pinchGesture)
                .simultaneousGesture(doubleTapGesture)

                // Controls
                VStack {
                    HStack {
                        Button { onCancel() } label: {
                            Text(L10n.t("إلغاء", "Cancel"))
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.error)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }

                        Spacer()

                        Text(L10n.t("تعديل الصورة", "Edit Photo"))
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textPrimary)

                        Spacer()

                        Button {
                            let cropped = performCrop()
                            onCrop(cropped)
                        } label: {
                            Text(L10n.t("تأكيد", "Confirm"))
                                .font(DS.Font.calloutBold)
                                .foregroundColor(DS.Color.textOnPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(DS.Color.primary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 60)

                    Spacer()

                    Text(L10n.t("اسحب وكبّر الصورة للتعديل", "Drag and pinch to adjust"))
                        .font(DS.Font.scaled(13))
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.bottom, 50)
                }
            }
            .onAppear {
                containerSize = geometry.size
            }
            .onChange(of: geometry.size) {
                containerSize = geometry.size
            }
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            displayImage = downsample(image, maxSize: maxDisplaySize)
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                scale = min(max(newScale, 0.5), 5.0)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    // MARK: - Overlay

    private func cropOverlay(cropSize: CGFloat, screenW: CGFloat, screenH: CGFloat) -> some View {
        ZStack {
            // خلفية شبه شفافة
            Color(uiColor: .systemBackground).opacity(0.7)

            // فتحة القص
            Group {
                if cropShape == .circle {
                    Circle()
                        .frame(width: cropSize, height: cropSize)
                        .blendMode(.destinationOut)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .frame(width: cropSize, height: cropSize)
                        .blendMode(.destinationOut)
                }
            }

            // إطار القص
            Group {
                if cropShape == .circle {
                    Circle()
                        .stroke(DS.Color.primary.opacity(0.6), lineWidth: 2)
                        .frame(width: cropSize, height: cropSize)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Color.primary.opacity(0.6), lineWidth: 2)
                        .frame(width: cropSize, height: cropSize)
                }
            }
        }
        .frame(width: screenW, height: screenH)
        .compositingGroup()
    }

    // MARK: - Downsample

    private func downsample(_ source: UIImage, maxSize: CGFloat) -> UIImage {
        let w = source.size.width
        let h = source.size.height
        guard max(w, h) > maxSize else { return source }

        let ratio = maxSize / max(w, h)
        let newSize = CGSize(width: w * ratio, height: h * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Crop

    private func performCrop() -> UIImage {
        let sourceImage = image
        let imageSize = sourceImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return sourceImage }

        // مطابقة حسابات العرض بالضبط
        let viewCropSize = max(min(containerSize.width - 40, containerSize.height * 0.55), 44)
        let frameSize = viewCropSize * 1.5

        // scaledToFill: الصورة تملأ الإطار بالكامل (البعد الأصغر يطابق الإطار)
        let imageAspect = imageSize.width / imageSize.height
        let frameAspect: CGFloat = 1.0 // الإطار مربع

        var renderedWidth: CGFloat
        var renderedHeight: CGFloat

        if imageAspect > frameAspect {
            // الصورة أعرض — الارتفاع يطابق الإطار
            renderedHeight = frameSize
            renderedWidth = frameSize * imageAspect
        } else {
            // الصورة أطول — العرض يطابق الإطار
            renderedWidth = frameSize
            renderedHeight = frameSize / imageAspect
        }

        // تطبيق الـ scale
        renderedWidth *= scale
        renderedHeight *= scale

        // مركز الصورة المعروضة يتوسط الشاشة
        // الـ offset يحرك الصورة، لذا مركز القص بالنسبة للصورة هو:
        // (نصف حجم الصورة المعروضة - الإزاحة)
        let cropCenterInImageViewX = renderedWidth / 2 - offset.width
        let cropCenterInImageViewY = renderedHeight / 2 - offset.height

        // تحويل من إحداثيات العرض إلى إحداثيات الصورة الأصلية
        let ratioX = imageSize.width / renderedWidth
        let ratioY = imageSize.height / renderedHeight

        let realCenterX = cropCenterInImageViewX * ratioX
        let realCenterY = cropCenterInImageViewY * ratioY
        let realCropSize = viewCropSize * ratioX

        var cropRect = CGRect(
            x: realCenterX - realCropSize / 2,
            y: realCenterY - realCropSize / 2,
            width: realCropSize,
            height: realCropSize
        )

        // ضمان عدم الخروج عن حدود الصورة
        cropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))

        guard !cropRect.isEmpty,
              let cgImage = sourceImage.cgImage?.cropping(to: cropRect) else {
            return sourceImage
        }

        let croppedImage = UIImage(cgImage: cgImage, scale: sourceImage.scale, orientation: sourceImage.imageOrientation)

        return croppedImage
    }
}
