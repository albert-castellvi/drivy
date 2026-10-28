import CoreGraphics

/// The measurements of the road, shared by every component of `Drivy/UI/Road`
/// (S3). They come from the approved mockup: a 64 pt band with 3 pt edge lines
/// and a 4 pt centre dash, and 28 pt between the asphalt and the content.
enum RoadMetrics {

    /// Width of the asphalt band the stops are pinned on.
    static let roadWidth: CGFloat = 64

    /// The solid white line that defines the edge of the road. It is what makes
    /// the band read as a road in dark mode, where the asphalt is only slightly
    /// lighter than the paper.
    static let edgeLineWidth: CGFloat = 3

    /// Width of the dashed centre line.
    static let centreLineWidth: CGFloat = 4

    /// Length of one centre dash.
    static let dashLength: CGFloat = 22

    /// Gap between two centre dashes: one cycle of the moving road is
    /// `dashLength + dashGap`.
    static let dashGap: CGFloat = 18

    /// Space between the asphalt and the content of a stop.
    static let contentGap: CGFloat = 28

    /// Vertical space between two stops.
    static let stopSpacing: CGFloat = 6

    /// The design size of a sign used as a pin.
    static let signSize: CGFloat = 44

    /// The smallest size a sign is drawn at: below it the glyph stops reading.
    static let minSignSize: CGFloat = 24

    /// The largest size a sign is drawn at: above it a row of signs outweighs
    /// the text it belongs to.
    static let maxSignSize: CGFloat = 64
}
