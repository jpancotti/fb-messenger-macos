import AppKit
import WebKit

/// Custom `WKWebView` that allows dragging the unified borderless titlebar along the top edge
/// and around the inset traffic lights without blocking Messenger's header buttons.
final class MessengerWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }

        let distanceFromTop = isFlipped ? localPoint.y : (bounds.height - localPoint.y)

        // Top 14pt drag strip across the window, plus 76x38pt around the top-left traffic lights
        let isTopDragStrip = distanceFromTop <= 14
        let isTrafficLightZone = localPoint.x <= 76 && distanceFromTop <= 38

        if isTopDragStrip || isTrafficLightZone {
            return nil
        }
        return super.hitTest(point)
    }
}
