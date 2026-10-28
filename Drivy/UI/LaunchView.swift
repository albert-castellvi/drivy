import SwiftUI

/// The identity of the app (S5): a short stretch of road with its lane marks,
/// above the wordmark in the display role.
///
/// It replaces the car icon and the spinner: the road says what the app is, and
/// when it moves it says that something is happening on it (S9). The strip is
/// decorative — the wordmark carries the name — and the height grows with the
/// user's text size instead of staying frozen.
struct RoadIdentityMark: View {

    /// `true` while the wait is real (the token exchange in flight), so the
    /// centre line scrolls. Reduce Motion stops it inside `RoadSurface` (S9).
    var isMoving: Bool = false

    @ScaledMetric(relativeTo: .body) private var stripWidth: CGFloat = RoadMetrics.roadWidth

    @ScaledMetric(relativeTo: .body) private var stripHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 14) {
            RoadSurface(isMoving: isMoving)
                .frame(width: stripWidth, height: stripHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            Text(DrivyConfig.appDisplayName)
                .font(.drivyDisplay)
                .foregroundStyle(Color.drivyInk)
        }
    }
}

/// Shown while the persisted session is being read from the Keychain.
struct LaunchView: View {

    var body: some View {
        RoadIdentityMark()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.drivyPaper)
    }
}

/// Shown while the Apple sheet / token exchange is in flight.
struct AuthenticatingView: View {

    var body: some View {
        VStack(spacing: 20) {
            RoadIdentityMark(isMoving: true)

            Text("Conectando con tu cuenta…")
                .font(.drivyBody)
                .foregroundStyle(Color.drivyInkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.drivyPaper)
    }
}

#Preview {
    LaunchView()
}

#Preview("Conectando") {
    AuthenticatingView()
}
