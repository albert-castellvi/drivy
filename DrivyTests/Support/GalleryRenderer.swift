import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Drivy

/// S8: the visual proof of the redesign. One test renders one gallery sheet twice —
/// light and dark — and, when `GALLERY_DIR` is set (CI does it with
/// `TEST_RUNNER_GALLERY_DIR`), writes `<name>-light.png` and `<name>-dark.png` into
/// that folder for the `design-gallery` artifact.
///
/// The sheet is hosted in a real window and captured with `drawHierarchy`, not
/// `ImageRenderer`: `ImageRenderer` draws a placeholder for every UIKit-backed view
/// (`ScrollView`, `List`, `Form`, `Map`), which is most of the app's screens. The
/// tests run inside the app (`TEST_HOST`), so a window scene is available.
@MainActor
func renderGallery<V: View>(
    _ name: String,
    width: CGFloat = 390,
    height: CGFloat = 844,
    @ViewBuilder _ content: () -> V
) {
    for scheme in [ColorScheme.light, ColorScheme.dark] {
        renderGallerySheet(
            name,
            scheme: scheme,
            width: width,
            height: height,
            sheet: content()
        )
    }
}

@MainActor
private func renderGallerySheet<V: View>(
    _ name: String,
    scheme: ColorScheme,
    width: CGFloat,
    height: CGFloat,
    sheet: V
) {
    let appearance = galleryAppearanceName(scheme)
    // The scheme goes last so the page background resolves in it too; a
    // modifier applied after `.environment` sits outside its scope.
    let page = sheet
        .frame(width: width, height: height)
        .background(Color.drivyPaper)
        // Same root modifiers as `DrivyApp`, so a sheet shows what the app shows.
        .tint(Color.drivyTint)
        .font(.drivyBody)
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(scheme)

    let renderedImage = snapshotInWindow(page, scheme: scheme, width: width, height: height)
    XCTAssertNotNil(
        renderedImage,
        "no snapshot for gallery \"\(name)\" in \(appearance) mode (\(Int(width))×\(Int(height)) pt)"
    )

    guard let image = renderedImage, let directory = galleryDirectory() else { return }

    guard let data = image.pngData() else {
        XCTFail("pngData() returned nil for gallery \"\(name)\" in \(appearance) mode")
        return
    }

    let url = directory.appendingPathComponent("\(name)-\(appearance).png")
    do {
        try data.write(to: url, options: Data.WritingOptions.atomic)
    } catch {
        XCTFail(
            "could not write \(url.path) for gallery \"\(name)\" in \(appearance) mode: \(error)"
        )
    }
}

/// Hosts `page` in its own window at `width` × `height`, lets SwiftUI lay it out,
/// and draws the window hierarchy at scale 3. The window is torn down afterwards
/// so the next sheet starts clean.
@MainActor
private func snapshotInWindow<V: View>(
    _ page: V,
    scheme: ColorScheme,
    width: CGFloat,
    height: CGFloat
) -> UIImage? {
    let frame = CGRect(x: 0, y: 0, width: width, height: height)
    let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light

    let host = UIHostingController(rootView: page)
    host.overrideUserInterfaceStyle = style

    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first
    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: frame)
    window.frame = frame
    window.overrideUserInterfaceStyle = style
    window.rootViewController = host
    window.isHidden = false
    host.view.frame = frame
    host.view.layoutIfNeeded()

    // Lists and scroll views populate on the next run-loop turns.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))

    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    format.opaque = true
    let image = UIGraphicsImageRenderer(bounds: frame, format: format).image { _ in
        _ = window.drawHierarchy(in: frame, afterScreenUpdates: true)
    }

    window.isHidden = true
    window.rootViewController = nil
    return image.size == .zero ? nil : image
}

/// `light` / `dark`: the suffix of the PNG and the word a failure uses.
private func galleryAppearanceName(_ scheme: ColorScheme) -> String {
    scheme == .dark ? "dark" : "light"
}

/// The folder of `GALLERY_DIR`, created on demand, or `nil` when the variable is
/// unset or empty — a local run then renders, asserts and writes nothing.
@MainActor
private func galleryDirectory() -> URL? {
    let path = ProcessInfo.processInfo.environment["GALLERY_DIR"] ?? ""
    guard !path.isEmpty else { return nil }

    let directory = URL(fileURLWithPath: path, isDirectory: true)
    do {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    } catch {
        XCTFail("could not create GALLERY_DIR at \(directory.path): \(error)")
        return nil
    }
    return directory
}
