//
//  SideDrawerContainer.swift
//  SideDrawer
//
//  Side drawer container.
//

import SwiftUI

// MARK: - Side drawer container
//
// A single `progress` (0 = closed, 1 = open) drives everything: the main
// page's offset and the tap/drag catcher. During a drag it is updated with
// `interactiveSpring` so a new touch smoothly redirects any in-flight release
// animation (no jump). On release, `predictedEndTranslation` (velocity-aware)
// decides open vs. close, so a flick also toggles it.
//
// `isOpen` is a two-way binding: external buttons set it; the drawer's own
// gestures sync it back. A full-height transparent grabber on the `edge` side
// (top of the ZStack) wins the edge drag so it isn't stolen by an inner ScrollView.
//
// Corners use `ContainerRelativeShape`, which is concentric with the enclosing
// container — on iOS the window provides a container shape matching the screen,
// so the card's corners match the device with no private API. Pass an explicit
// `cornerRadius` to override with a fixed radius instead.

public struct SideDrawerContainer<Menu: View, Content: View>: View {

    /// Two-way open/close switch shared with the caller.
    @Binding private var isOpen: Bool

    /// Which side the drawer slides from. All geometry mirrors accordingly.
    private let edge: HorizontalEdge

    /// Menu width as a fraction of the screen width.
    private let menuWidthRatio: CGFloat

    /// Edge band width (full height) that can pull the drawer open when closed.
    private let edgeWidth: CGFloat

    /// Main-page corner radius. `nil` matches the screen via `ContainerRelativeShape`.
    private let cornerRadius: CGFloat?

    private let menu: () -> Menu
    private let content: () -> Content

    /// 0 = closed, 1 = open (slight overshoot allowed for rubber-banding).
    @State private var progress: CGFloat = 0
    /// Progress captured at touch-down, used as the baseline for the drag.
    @State private var dragStartProgress: CGFloat?
    /// Whether the current outer drag started in the closed drawer's edge band.
    @State private var edgeDragAccepted: Bool?

    /// Creates a side drawer.
    /// - Parameters:
    ///   - isOpen: Two-way binding controlling open/closed state.
    ///   - edge: Side the drawer slides from. Default `.leading`.
    ///   - menuWidthRatio: Menu width as a fraction of screen width. Default `0.8`.
    ///   - edgeWidth: Width of the edge band that pulls the drawer open. Default `24`.
    ///   - cornerRadius: Fixed main-page corner radius. `nil` matches the screen. Default `nil`.
    ///   - menu: The drawer (sits underneath, full screen).
    ///   - content: The main page (slides over the menu).
    public init(
        isOpen: Binding<Bool>,
        edge: HorizontalEdge = .leading,
        menuWidthRatio: CGFloat = 0.8,
        edgeWidth: CGFloat = 200,
        cornerRadius: CGFloat? = nil,
        @ViewBuilder menu: @escaping () -> Menu,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isOpen = isOpen
        self.edge = edge
        self.menuWidthRatio = menuWidthRatio
        self.edgeWidth = edgeWidth
        self.cornerRadius = cornerRadius
        self.menu = menu
        self.content = content
    }

    /// +1 = leading (main moves right), -1 = trailing (main moves left).
    private var direction: CGFloat { edge == .leading ? 1 : -1 }

    /// Square when closed (full-bleed, so no corner leaks the menu), and the
    /// screen-matched / fixed shape once it starts opening.
    private func mainShape(open: Bool) -> AnyShape {
        guard open else { return AnyShape(Rectangle()) }
        if let cornerRadius {
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        return AnyShape(ContainerRelativeShape())
    }

    public var body: some View {
        GeometryReader { geo in
            let menuWidth = geo.size.width * menuWidthRatio
            let p = progress
            let clamped = min(max(p, 0), 1)
            let shift = direction * p * menuWidth

            ZStack(alignment: edge == .leading ? .leading : .trailing) {

                // Menu: full-screen bottom layer, stays interactive.
                menu()

                // Main page: content moved as one unit (single offset).
                ZStack {
                    content()
                        .clipShape(mainShape(open: p > 0.001))
                        .ignoresSafeArea()

                    // Tap/drag-to-close catcher. Lives inside the offset stack, so
                    // it only covers the main page and never blocks the menu.
                    if p > 0.01 {
                        Color.clear
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { animate(to: 0) }
                    }
                }
                .shadow(color: .black.opacity(0.12 * Double(clamped)),
                        radius: 24, x: direction * -8, y: 0)
                .offset(x: shift)

            }
            .simultaneousGesture(edgeDragGesture(containerWidth: geo.size.width, menuWidth: menuWidth))
        }
        // Medium impact on every open/close.
        .sensoryFeedback(.impact(weight: .medium), trigger: isOpen)
        // onChange doesn't fire for the initial value, so align progress on appear.
        .onAppear { progress = isOpen ? 1 : 0 }
        .onChange(of: isOpen) { _, open in
            animate(to: open ? 1 : 0)
        }
    }

    // MARK: Gesture

    private func dragGesture(menuWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if dragStartProgress == nil {
                    dragStartProgress = progress
                }
                let base = dragStartProgress ?? 0
                var p = base + direction * value.translation.width / menuWidth

                // Rubber-band the out-of-range part.
                if p < 0 { p = p * 0.18 }
                if p > 1 { p = 1 + (p - 1) * 0.18 }

                // interactiveSpring tracks the finger and smoothly interrupts
                // any in-flight release animation.
                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86)) {
                    progress = p
                }
            }
            .onEnded { value in
                let base = dragStartProgress ?? progress
                dragStartProgress = nil
                // Velocity-aware end point: a flick toggles too.
                let predicted = base + direction * value.predictedEndTranslation.width / menuWidth
                animate(to: predicted > 0.5 ? 1 : 0)
            }
    }

    private func edgeDragGesture(containerWidth: CGFloat, menuWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if edgeDragAccepted == nil {
                    edgeDragAccepted = shouldAcceptDragStart(value, containerWidth: containerWidth)
                }
                guard edgeDragAccepted == true else { return }

                if dragStartProgress == nil {
                    dragStartProgress = progress
                }
                let base = dragStartProgress ?? 0
                var p = base + direction * value.translation.width / menuWidth

                // Rubber-band the out-of-range part.
                if p < 0 { p = p * 0.18 }
                if p > 1 { p = 1 + (p - 1) * 0.18 }

                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86)) {
                    progress = p
                }
            }
            .onEnded { value in
                defer {
                    edgeDragAccepted = nil
                    dragStartProgress = nil
                }
                guard edgeDragAccepted == true else { return }

                let base = dragStartProgress ?? progress
                let predicted = base + direction * value.predictedEndTranslation.width / menuWidth
                animate(to: predicted > 0.5 ? 1 : 0)
            }
    }

    private func shouldAcceptDragStart(_ value: DragGesture.Value, containerWidth: CGFloat) -> Bool {
        if progress <= 0.01 {
            return startsInEdgeBand(value.startLocation, containerWidth: containerWidth)
        }

        if progress >= 0.01 {
            return direction * value.translation.width < 0
        }

        return false
    }

    private func startsInEdgeBand(_ location: CGPoint, containerWidth: CGFloat) -> Bool {
        switch edge {
        case .leading:
            return location.x <= edgeWidth
        case .trailing:
            return location.x >= containerWidth - edgeWidth
        }
    }

    private func animate(to target: CGFloat) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            progress = target
        }
        let shouldOpen = target > 0.5
        if isOpen != shouldOpen { isOpen = shouldOpen }
    }
}
