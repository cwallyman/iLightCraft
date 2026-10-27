import SwiftUI
import UIKit

/// Main-photo interaction viewport. Image, coverage and handles share one zoom transform;
/// tool coordinates always refer to the uncropped, oriented engine preview, never the dock.
struct PhotoToolViewport: UIViewRepresentable {
    enum Mode { case masks, remove, crop, guides, radial }
    struct ZoomRequest: Equatable {
        enum Action: Equatable { case fit, zoomIn, zoomOut, percent(Double) }
        let id = UUID()
        let action: Action
    }
    let image: UIImage
    let mode: Mode
    var mask: UIImage?
    var sourcePoint: CGPoint?
    var maskPin: CGPoint?
    var stroke: [CGPoint] = []
    var guideLines: [[CGPoint]] = []
    var onGuideFinished: () -> Void = {}
    var brushSize = 0.025
    var picking = false
    var crop = CropSettings.Rectangle()
    var ratio: CGFloat?
    var angle = 0.0
    var busy = false
    var zoomRequest: ZoomRequest?
    var onPick: (CGPoint) -> Void = { _ in }
    var onStroke: ([CGPoint]) -> Void = { _ in }
    var onCrop: (CropSettings.Rectangle) -> Void = { _ in }
    var onInteraction: (Bool) -> Void = { _ in }
    var sourcePixelWidth: CGFloat?
    var selectionRadius: Double?
    var onZoomPercent: (Double) -> Void = { _ in }
    var cropOverlay = "thirds"
    var cropOverlayFlipped = false

    func makeUIView(context: Context) -> PhotoToolScrollView { PhotoToolScrollView() }
    func updateUIView(_ view: PhotoToolScrollView, context: Context) { view.configure(self) }
    static func dismantleUIView(_ view: PhotoToolScrollView, coordinator: ()) {
        view.close()
    }
}

final class PhotoToolScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    fileprivate var photo: PhotoToolViewport?
    private let surface = PhotoToolDrawingView()
    private var imageSize = CGSize.zero
    private var viewportSize = CGSize.zero
    private var lastZoomRequest: UUID?
    private var lastZoomPercent = -1.0
    private var fitting = false
    private var initialCrop: CGRect?
    private var cropCorner: Int?
    private var initialStroke: [CGPoint] = []
    private var startPoint = CGPoint.zero
    private var drawing = false
    private var panGesture: UIPanGestureRecognizer?
    private var tapGesture: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.1, alpha: 1)
        delegate = self
        minimumZoomScale = 1; maximumZoomScale = 8
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        // One finger belongs to the tool. Pinch and two-finger pan belong to navigation.
        panGestureRecognizer.minimumNumberOfTouches = 2
        addSubview(surface)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drawGesture(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
        pan.delegate = self; surface.addGestureRecognizer(pan); panGesture = pan
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapPhoto(_:)))
        tap.delegate = self; surface.addGestureRecognizer(tap); tapGesture = tap
        accessibilityLabel = "Main photo editing surface"
        accessibilityHint = "Pinch to zoom. Pan with two fingers. Use one finger to edit."
    }
    required init?(coder: NSCoder) { return nil }

    func configure(_ photo: PhotoToolViewport) {
        self.photo = photo
        surface.photo = photo
        if imageSize != photo.image.size {
            imageSize = photo.image.size
            viewportSize = .zero
            setZoomScale(1, animated: false)
            setNeedsLayout()
        }
        surface.setNeedsDisplay()
        panGesture?.isEnabled = !photo.busy && (photo.mode == .remove || photo.mode == .crop || photo.mode == .guides || photo.mode == .radial)
        tapGesture?.isEnabled = !photo.busy && (photo.mode == .remove || photo.picking)
        pinchGestureRecognizer?.isEnabled = !photo.busy
        panGestureRecognizer.isEnabled = !photo.busy
        if let request = photo.zoomRequest, request.id != lastZoomRequest {
            lastZoomRequest = request.id
            switch request.action {
            case .fit: setZoomScale(1, animated: false); centerImage()
            case .zoomIn: setZoomScale(min(maximumZoomScale, zoomScale * 1.5), animated: false)
            case .zoomOut: setZoomScale(max(minimumZoomScale, zoomScale / 1.5), animated: false)
            case .percent(let percent):
                let sourceWidth = photo.sourcePixelWidth ?? imageSize.width
                let fitPercent = sourceWidth > 0 ? Double(surface.bounds.width * (window?.screen.scale ?? 1) / sourceWidth * 100) : 0
                if percent.isFinite, percent > 0, fitPercent.isFinite, fitPercent > 0 {
                    minimumZoomScale = CGFloat(min(1, ZoomScale.minimumPercent / fitPercent))
                    maximumZoomScale = CGFloat(max(1, ZoomScale.maximumPercent / fitPercent))
                    setZoomScale(CGFloat(min(ZoomScale.maximumPercent, max(ZoomScale.minimumPercent, percent)) / fitPercent), animated: false)
                    centerImage()
                }
            }
        }
    }
    func close() {
        photo?.onInteraction(false)
        photo = nil; surface.photo = nil; delegate = nil
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !fitting, bounds.size.width > 0, bounds.size.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return }
        if viewportSize != bounds.size {
            fitting = true
            let priorZoom = zoomScale
            let center = surface.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self)
            let priorSize = surface.bounds.size
            let normalized = CGPoint(x: priorSize.width > 0 ? center.x / priorSize.width : 0.5,
                                     y: priorSize.height > 0 ? center.y / priorSize.height : 0.5)
            setZoomScale(1, animated: false)
            let scale = min(max(1, bounds.width - 32) / imageSize.width,
                            max(1, bounds.height - 32) / imageSize.height)
            surface.frame = CGRect(origin: .zero, size: CGSize(width: imageSize.width * scale, height: imageSize.height * scale))
            contentSize = surface.bounds.size
            viewportSize = bounds.size
            setZoomScale(priorZoom, animated: false)
            centerImage()
            let target = CGPoint(x: normalized.x * surface.bounds.width * zoomScale - bounds.width / 2,
                                 y: normalized.y * surface.bounds.height * zoomScale - bounds.height / 2)
            contentOffset = CGPoint(x: min(max(-contentInset.left, target.x), max(-contentInset.left, contentSize.width - bounds.width + contentInset.right)),
                                    y: min(max(-contentInset.top, target.y), max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)))
            fitting = false
        }
        centerImage()
    }
    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let next = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != next { contentInset = next }
        surface.handleScale = zoomScale
        let pixels = photo?.sourcePixelWidth ?? imageSize.width
        if pixels > 0 {
            let percent = Double(surface.bounds.width * zoomScale * (window?.screen.scale ?? 1) / pixels * 100)
            if percent.isFinite, percent > 0, abs(percent - lastZoomPercent) > 0.01, let onZoom = photo?.onZoomPercent {
                lastZoomPercent = percent
                DispatchQueue.main.async { onZoom(percent) }
            }
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { surface }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(); surface.setNeedsDisplay() }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { photo?.onInteraction(true) }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { photo?.onInteraction(false) }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { photo?.onInteraction(true) }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { photo?.onInteraction(false) }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { photo?.onInteraction(false) }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let photo, !photo.busy else { return false }
        if gestureRecognizer === panGesture || gestureRecognizer === tapGesture {
            return photo.mode != .masks || photo.picking
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    private func normalized(_ point: CGPoint) -> CGPoint? {
        PhotoToolGeometry.normalized(point, size: surface.bounds.size)
    }
    @objc private func tapPhoto(_ gesture: UITapGestureRecognizer) {
        guard let photo, !photo.busy, let point = normalized(gesture.location(in: surface)) else { return }
        if photo.mode == .masks && photo.picking { photo.onPick(point) }
        if photo.mode == .remove {
            var points = photo.stroke
            if points.count < 2048 { points.append(point); photo.onStroke(points) }
        }
    }
    @objc private func drawGesture(_ gesture: UIPanGestureRecognizer) {
        guard let photo, let point = normalized(gesture.location(in: surface)) else { return }
        switch gesture.state {
        case .began:
            guard !photo.busy else { return }
            initialStroke = photo.stroke; startPoint = point
            if photo.mode == .crop {
                let rect = photo.crop.cgRect
                let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                               CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
                cropCorner = corners.indices.min { a, b in
                    distance(corners[a], point) < distance(corners[b], point)
                }
                if let corner = cropCorner, let position = corners.dropFirst(corner).first,
                   distance(position, point) > 30 / max(1, zoomScale) { cropCorner = nil }
                guard cropCorner != nil || rect.contains(point) else { return }
                initialCrop = rect
            }
            drawing = true; photo.onInteraction(true)
            if photo.mode == .remove { append(point) }
        case .changed:
            guard drawing, !photo.busy else { return }
            if photo.mode == .remove { append(point) }
            if photo.mode == .guides || photo.mode == .radial { photo.onStroke([startPoint, point]) }
            if photo.mode == .crop, let initialCrop {
                let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
                photo.onCrop(CropSettings.Rectangle(PhotoToolGeometry.crop(initialCrop, corner: cropCorner, delta: delta,
                                                                          ratio: photo.ratio, imageSize: photo.image.size)))
            }
        case .cancelled, .failed:
            if drawing {
                if photo.mode == .remove || photo.mode == .guides || photo.mode == .radial { photo.onStroke(initialStroke) }
                if let initialCrop, photo.mode == .crop { photo.onCrop(.init(initialCrop)) }
            }
            finish()
        case .ended:
            if drawing && photo.mode == .guides { photo.onGuideFinished() }
            finish()
        default: break
        }
    }
    private func finish() { drawing = false; initialCrop = nil; photo?.onInteraction(false) }
    private func append(_ point: CGPoint) {
        guard let photo, photo.stroke.count < 2048 else { return }
        var points = photo.stroke
        if let last = points.last, distance(last, point) < 1 / max(1, zoomScale) { return }
        points.append(point)
        self.photo?.stroke = points; surface.photo?.stroke = points; surface.setNeedsDisplay()
        photo.onStroke(points)
    }
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot((a.x - b.x) * surface.bounds.width, (a.y - b.y) * surface.bounds.height)
    }
}

private final class PhotoToolDrawingView: UIView {
    var photo: PhotoToolViewport?
    var handleScale: CGFloat = 1
    override func draw(_ rect: CGRect) {
        guard let photo, let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: photo.angle * .pi / 180)
        photo.image.draw(in: CGRect(x: -bounds.width / 2, y: -bounds.height / 2, width: bounds.width, height: bounds.height))
        context.restoreGState()
        if let mask = photo.mask { mask.draw(in: bounds, blendMode: .normal, alpha: 0.35) }
        if let pin = photo.maskPin {
            let radius = 5 / max(1, handleScale)
            let marker = UIBezierPath(ovalIn: CGRect(x: pin.x * bounds.width - radius, y: pin.y * bounds.height - radius, width: radius * 2, height: radius * 2))
            UIColor.darkGray.setFill(); marker.fill()
            UIColor.white.setStroke(); marker.lineWidth = 1.5 / max(1, handleScale); marker.stroke()
        }
        if let source = photo.sourcePoint {
            let point = CGPoint(x: source.x * bounds.width, y: source.y * bounds.height)
            let radius = photo.selectionRadius.map { CGFloat($0) * max(bounds.width, bounds.height) } ?? (9 / max(1, handleScale))
            UIColor.systemCyan.setStroke()
            let marker = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            marker.lineWidth = 2 / max(1, handleScale); marker.stroke()
        }
        if photo.mode == .remove, let first = photo.stroke.first {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: first.x * bounds.width, y: first.y * bounds.height))
            for point in photo.stroke.dropFirst() { path.addLine(to: CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)) }
            if photo.stroke.count == 1 { path.addLine(to: CGPoint(x: first.x * bounds.width + 0.01, y: first.y * bounds.height)) }
            path.lineWidth = max(1, photo.brushSize * max(bounds.width, bounds.height) * 2)
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            UIColor.systemYellow.withAlphaComponent(0.6).setStroke(); path.stroke()
        }
        if photo.mode == .radial, let a = photo.stroke.first, let b = photo.stroke.last, photo.stroke.count > 1 {
            let rx = max(2, abs(b.x - a.x) * bounds.width), ry = max(2, abs(b.y - a.y) * bounds.height)
            UIColor.systemYellow.setStroke()
            let path = UIBezierPath(ovalIn: CGRect(x: a.x * bounds.width - rx, y: a.y * bounds.height - ry, width: rx * 2, height: ry * 2))
            path.lineWidth = 2 / max(1, handleScale); path.stroke()
        }
        if photo.mode == .guides {
            UIColor.systemYellow.setStroke()
            for line in photo.guideLines + [photo.stroke] {
                guard let a = line.first, let b = line.last, line.count > 1 else { continue }
                let path = UIBezierPath(); path.lineWidth = 2 / max(1, handleScale)
                path.move(to: CGPoint(x: a.x * bounds.width, y: a.y * bounds.height))
                path.addLine(to: CGPoint(x: b.x * bounds.width, y: b.y * bounds.height)); path.stroke()
            }
        }
        if photo.mode == .crop {
            let r = photo.crop.cgRect
            let crop = CGRect(x: r.minX * bounds.width, y: r.minY * bounds.height, width: r.width * bounds.width, height: r.height * bounds.height)
            let shade = UIBezierPath(rect: bounds); shade.append(UIBezierPath(rect: crop)); shade.usesEvenOddFillRule = true
            UIColor.black.withAlphaComponent(0.55).setFill(); shade.fill()
            UIColor.white.setStroke(); let border = UIBezierPath(rect: crop); border.lineWidth = 1 / max(1, handleScale); border.stroke()
            let grid = NativeCropGuides.path(in: crop, kind: photo.cropOverlay, flipped: photo.cropOverlayFlipped)
            context.saveGState(); context.clip(to: crop)
            grid.lineWidth = 0.5 / max(1, handleScale); grid.stroke()
            context.restoreGState()
            UIColor.white.setFill()
            let radius = 6 / max(1, handleScale)
            for x in [crop.minX, crop.maxX] { for y in [crop.minY, crop.maxY] {
                UIBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
            } }
        }
    }
}

nonisolated enum PhotoToolGeometry {
    static func normalized(_ point: CGPoint, size: CGSize) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return CGPoint(x: min(1, max(0, point.x / size.width)), y: min(1, max(0, point.y / size.height)))
    }

    static func crop(_ rect: CGRect, corner: Int?, delta: CGPoint, ratio: CGFloat?, imageSize: CGSize) -> CGRect {
        guard delta.x.isFinite, delta.y.isFinite else { return rect }
        guard let corner else {
            return CGRect(x: min(1 - rect.width, max(0, rect.minX + delta.x)), y: min(1 - rect.height, max(0, rect.minY + delta.y)), width: rect.width, height: rect.height)
        }
        let left = corner % 2 == 0, top = corner < 2
        let anchor = CGPoint(x: left ? rect.maxX : rect.minX, y: top ? rect.maxY : rect.minY)
        let x = min(1, max(0, (left ? rect.minX : rect.maxX) + delta.x))
        let y = min(1, max(0, (top ? rect.minY : rect.maxY) + delta.y))
        let maxWidth = left ? anchor.x : 1 - anchor.x, maxHeight = top ? anchor.y : 1 - anchor.y
        var width = min(maxWidth, max(0.03, left ? anchor.x - x : x - anchor.x))
        var height = min(maxHeight, max(0.03, top ? anchor.y - y : y - anchor.y))
        if let ratio, ratio.isFinite, ratio > 0, imageSize.width > 0, imageSize.height > 0 {
            let normalized = ratio * imageSize.height / imageSize.width
            width = min(width, maxHeight * normalized); height = width / normalized
        }
        return CGRect(x: left ? anchor.x - width : anchor.x, y: top ? anchor.y - height : anchor.y, width: width, height: height)
    }
}
