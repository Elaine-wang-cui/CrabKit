import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 把相册、相机、文件里拿到的东西变成附件
enum AttachmentLoader {
    /// 图片长边压到 1568，再大只是更占内存
    static func image(_ ui: UIImage, name: String = "Image") -> Attachment? {
        let resized = ui.fitted(maxSide: 1568)
        guard let jpg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return Attachment(kind: .image, name: name, mediaType: "image/jpeg", data: jpg)
    }

    static func image(data: Data, name: String = "Image") -> Attachment? {
        guard let ui = UIImage(data: data) else { return nil }
        return image(ui, name: name)
    }

    /// 文件：图片当图片，PDF 原样，其他能当 UTF-8 读的当文本，都不是就不收
    static func file(at url: URL) -> Attachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .image) {
            return image(data: data, name: name)
        }
        if let type, type.conforms(to: .pdf) {
            guard data.count < 30_000_000 else { return nil }
            return Attachment(kind: .pdf, name: name, mediaType: "application/pdf", data: data)
        }
        guard data.count < 2_000_000, String(data: data, encoding: .utf8) != nil else { return nil }
        return Attachment(kind: .text, name: name, mediaType: "text/plain", data: data)
    }
}

extension UIImage {
    func fitted(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let ratio = maxSide / longest
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// 缩略图解一次就记住
enum ThumbCache {
    private static let store = NSCache<NSUUID, UIImage>()

    static func image(for a: Attachment) -> UIImage? {
        if let hit = store.object(forKey: a.id as NSUUID) { return hit }
        guard let ui = UIImage(data: a.data) else { return nil }
        store.setObject(ui, forKey: a.id as NSUUID)
        return ui
    }
}

/// 圆角缩略图；文件显示成一个小卡片
struct AttachmentThumb: View {
    let attachment: Attachment
    var size: CGFloat = 120

    var body: some View {
        if attachment.kind == .image, let ui = ThumbCache.image(for: attachment) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
        } else {
            FileChip(attachment: attachment)
        }
    }
}

struct FileChip: View {
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "doc.text")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                Text(attachment.kind == .pdf ? "PDF" : "Text")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(8)
        .padding(.trailing, 6)
        .frame(maxWidth: 220, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 0.5))
    }
}

/// 点开图片：黑底，双指放大、拖动，双击放大或复原，往下一拉关掉
struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        if scale > 1 {
                            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                        } else {
                            scale = 2.5; lastScale = 2.5
                        }
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { v in scale = min(6, max(1, lastScale * v.magnification)) }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1 {
                                withAnimation(.snappy) { offset = .zero }
                                lastOffset = .zero
                            }
                        }
                        .simultaneously(with:
                            DragGesture()
                                .onChanged { v in
                                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                                    height: lastOffset.height + v.translation.height)
                                }
                                .onEnded { v in
                                    if scale <= 1 {
                                        if v.translation.height > 120 { dismiss(); return }
                                        withAnimation(.snappy) { offset = .zero }
                                        lastOffset = .zero
                                    } else {
                                        lastOffset = offset
                                    }
                                }
                        )
                )
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .padding(.trailing, 18)
            .padding(.top, 8)
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
    }
}

/// 系统相机
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
