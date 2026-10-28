import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import Drivy

/// S8: the visual proof of the redesign. One test renders one gallery sheet twice —
/// light and dark — through `ImageRenderer` and, when `GALLERY_DIR` is set (CI does
/// it with `TEST_RUNNER_GALLERY_DIR`), writes `<name>-light.png` and
/// `<name>-dark.png` into that folder for the `design-gallery` artifact.
///
/// `ImageRenderer` is main-actor bound, and `uiImage` is its only rasterization
/// surface on iOS (there is no `.image` and no `colorScheme` on the renderer): the
/// appearance is chosen on the view, with both the environment value and the
/// preferred scheme, and the sheet is pinned to `width` × `height` on `drivyPaper`
/// so the two renders cannot leak into each other through a parent.
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
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(scheme)

    let renderer = ImageRenderer(content: page)
    renderer.scale = 3
    renderer.isOpaque = true

    let renderedImage = renderer.uiImage
    XCTAssertNotNil(
        renderedImage,
        "ImageRenderer produced no image for gallery \"\(name)\" in \(appearance) mode (\(Int(width))×\(Int(height)) pt at scale 3)"
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
