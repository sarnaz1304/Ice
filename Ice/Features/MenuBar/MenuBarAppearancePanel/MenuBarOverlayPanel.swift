//
//  MenuBarOverlayPanel.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

// MARK: - MenuBarOverlayPanel

class MenuBarOverlayPanel: MenuBarAppearancePanel {
    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        super.init(level: .statusBar, menuBar: menuBar)
        self.contentView = MenuBarOverlayPanelView(menuBar: menuBar)
    }

    func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let menuBar {
            Publishers.CombineLatest3(
                menuBar.$tintKind,
                menuBar.$shapeKind,
                menuBar.$hasShadow
            )
            .map { tintKind, shapeKind, _ in
                tintKind != .none || shapeKind != .none
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                guard let self else {
                    return
                }
                if shouldShow {
                    show()
                } else {
                    hide()
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    override func menuBarFrame(forScreen screen: NSScreen) -> CGRect {
        let rect = super.menuBarFrame(forScreen: screen)
        return CGRect(
            x: rect.minX,
            y: rect.minY - 5,
            width: rect.width,
            height: rect.height + 5
        )
    }
}

// MARK: - MenuBarOverlayPanelView

private class MenuBarOverlayPanelView: NSView {
    private weak var menuBar: MenuBar?
    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        super.init(frame: .zero)
        self.menuBar = menuBar
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let menuBar {
            menuBar.$mainMenuMaxX
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)

            Publishers.CombineLatest4(
                menuBar.$desktopWallpaper,
                menuBar.$tintKind,
                menuBar.$tintColor,
                menuBar.$tintGradient
            )
            .combineLatest(
                menuBar.$shapeKind,
                menuBar.$fullShapeInfo,
                menuBar.$splitShapeInfo
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

            Publishers.CombineLatest4(
                menuBar.$hasShadow,
                menuBar.$hasBorder,
                menuBar.$borderColor,
                menuBar.$borderWidth
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

            for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
                if let section = menuBar.section(withName: name) {
                    section.controlItem.$windowFrame
                        .combineLatest(section.controlItem.$screen)
                        .filter { frame, screen in
                            guard
                                let frame,
                                let screen
                            else {
                                return false
                            }
                            return (screen.frame.minX...screen.frame.maxX).contains(frame.maxX)
                        }
                        .receive(on: RunLoop.main)
                        .sink { [weak self] _ in
                            self?.needsDisplay = true
                        }
                        .store(in: &c)
                }
            }
        }

        cancellables = c
    }

    /// Returns a path for the ``MenuBarShapeKind/full`` shape kind.
    private func pathForFullShapeKind(in rect: CGRect, info: MenuBarFullShapeInfo) -> NSBezierPath {
        let shapeBounds = CGRect(
            x: rect.height / 2,
            y: rect.origin.y,
            width: rect.width - rect.height,
            height: rect.height
        )
        let leadingEndCapBounds = CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.height,
            height: rect.height
        )
        let trailingEndCapBounds = CGRect(
            x: rect.width - rect.height,
            y: rect.origin.y,
            width: rect.height,
            height: rect.height
        )

        var path = NSBezierPath(rect: shapeBounds)

        path = switch info.leadingEndCap {
        case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
        }

        path = switch info.trailingEndCap {
        case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
        }

        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShapeKind(in rect: CGRect, info: MenuBarSplitShapeInfo) -> NSBezierPath {
        guard
            let menuBar,
            let hiddenSection = menuBar.section(withName: .hidden),
            let alwaysHiddenSection = menuBar.section(withName: .alwaysHidden)
        else {
            Logger.menuBarOverlayPanel.notice("Unable to create split shape path")
            return NSBezierPath(rect: rect)
        }

        guard alwaysHiddenSection.isHidden else {
            return pathForFullShapeKind(
                in: rect,
                info: MenuBarFullShapeInfo(
                    leadingEndCap: info.leading.leadingEndCap,
                    trailingEndCap: info.trailing.trailingEndCap
                )
            )
        }

        let leadingPath: NSBezierPath = {
            let shapeBounds = CGRect(
                x: rect.height / 2,
                y: rect.origin.y,
                width: (menuBar.mainMenuMaxX - rect.height) + 10,
                height: rect.height
            )
            let leadingEndCapBounds = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )
            let trailingEndCapBounds = CGRect(
                x: (menuBar.mainMenuMaxX - rect.height) + 10,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )

            var path = NSBezierPath(rect: shapeBounds)

            path = switch info.leading.leadingEndCap {
            case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

            path = switch info.leading.trailingEndCap {
            case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

            return path
        }()

        let trailingPath: NSBezierPath = {
            let position = if hiddenSection.isHidden {
                hiddenSection.controlItem.windowFrame?.maxX ?? 0
            } else {
                alwaysHiddenSection.controlItem.windowFrame?.maxX ?? 0
            }
            let shapeBounds = CGRect(
                x: (position + (rect.height / 2)) - 10,
                y: rect.origin.y,
                width: (rect.maxX - (position + rect.height)) + 10,
                height: rect.height
            )
            let leadingEndCapBounds = CGRect(
                x: position - 10,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )
            let trailingEndCapBounds = CGRect(
                x: rect.maxX - rect.height,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )

            var path = NSBezierPath(rect: shapeBounds)

            path = switch info.trailing.leadingEndCap {
            case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

            path = switch info.trailing.trailingEndCap {
            case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

            return path
        }()

        guard !leadingPath.intersects(trailingPath) else {
            return pathForFullShapeKind(
                in: rect,
                info: MenuBarFullShapeInfo(
                    leadingEndCap: info.leading.leadingEndCap,
                    trailingEndCap: info.trailing.trailingEndCap
                )
            )
        }

        let path = NSBezierPath()

        path.append(leadingPath)
        path.append(trailingPath)

        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let menuBar,
            let context = NSGraphicsContext.current
        else {
            return
        }

        context.saveGraphicsState()
        defer {
            context.restoreGraphicsState()
        }

        let adjustedBounds = CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )

        let shapePath = switch menuBar.shapeKind {
        case .none:
            NSBezierPath(rect: adjustedBounds)
        case .full:
            pathForFullShapeKind(in: adjustedBounds, info: menuBar.fullShapeInfo)
        case .split:
            pathForSplitShapeKind(in: adjustedBounds, info: menuBar.splitShapeInfo)
        }

        var hasBorder = false

        if menuBar.shapeKind != .none {
            if let desktopWallpaper = menuBar.desktopWallpaper {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let invertedClipPath = NSBezierPath(rect: adjustedBounds)
                invertedClipPath.append(shapePath.reversed)
                invertedClipPath.setClip()

                context.cgContext.draw(desktopWallpaper, in: adjustedBounds)
            }

            if menuBar.hasShadow {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()

                shapePath.drawShadow(color: .black.withAlphaComponent(0.5), radius: 5)
            }

            if menuBar.hasBorder {
                hasBorder = true
            }
        }

        shapePath.setClip()

        switch menuBar.tintKind {
        case .none:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: menuBar.tintColor)?.withAlphaComponent(0.2) {
                tintColor.setFill()
                NSBezierPath(rect: adjustedBounds).fill()
            }
        case .gradient:
            if let tintGradient = menuBar.tintGradient.withAlphaComponent(0.2).nsGradient {
                tintGradient.draw(in: adjustedBounds, angle: 0)
            }
        }

        if hasBorder {
            if let borderColor = NSColor(cgColor: menuBar.borderColor) {
                // swiftlint:disable:next force_cast
                let borderPath = shapePath.copy() as! NSBezierPath
                // HACK: insetting a path to get an "inside" stroke is surprisingly
                // difficult; we can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped
                borderPath.lineWidth = menuBar.borderWidth * 2
                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let menuBarOverlayPanel = Logger(category: "MenuBarOverlayPanel")
}