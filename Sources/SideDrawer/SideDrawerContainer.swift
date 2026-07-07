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
// gestures sync it back. The outer drag gesture first decides whether a touch
// belongs to the drawer or the page, so horizontal drawer drags, vertical
// ScrollView drags, and taps stay mutually exclusive.
//
// The main page stays square when closed, then rounds to a fixed continuous
// 56-point corner radius as it opens.

public struct SideDrawerContainer<Menu: View, Content: View>: View {

    /// Two-way open/close switch shared with the caller.
    @Binding private var isOpen: Bool

    /// Which side the drawer slides from. All geometry mirrors accordingly.
    private let edge: HorizontalEdge

    /// Menu width as a fraction of the screen width.
    private let menuWidthRatio: CGFloat

    /// Edge band width (full height) that can pull the drawer open when closed.
    private let edgeWidth: CGFloat

    private let menu: () -> Menu
    private let content: () -> Content

    /// 0 = closed, 1 = open (slight overshoot allowed for rubber-banding).
    @State private var progress: CGFloat = 0
    /// Progress captured at touch-down, used as the baseline for the drag.
    @State private var dragStartProgress: CGFloat?
    /// Whether the current outer drag started in the closed drawer's edge band.
    @State private var edgeDragAccepted: Bool?
    /// Owner for the current drag sequence, chosen after movement passes a threshold.
    @State private var dragOwner: DragOwner?
    /// Temporarily blocks page taps after a drawer drag has claimed the touch.
    @State private var suppressContentInteraction = false

    /// Creates a side drawer.
    /// - Parameters:
    ///   - isOpen: Two-way binding controlling open/closed state.
    ///   - edge: Side the drawer slides from. Default `.leading`.
    ///   - menuWidthRatio: Menu width as a fraction of screen width. Default `0.8`.
    ///   - edgeWidth: Width of the edge band that pulls the drawer open. Default `200`.
    ///   - menu: The drawer (sits underneath, full screen).
    ///   - content: The main page (slides over the menu).
    public init(
        isOpen: Binding<Bool>,
        edge: HorizontalEdge = .leading,
        menuWidthRatio: CGFloat = 0.8,
        edgeWidth: CGFloat = 200,
        @ViewBuilder menu: @escaping () -> Menu,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isOpen = isOpen
        self.edge = edge
        self.menuWidthRatio = menuWidthRatio
        self.edgeWidth = edgeWidth
        self.menu = menu
        self.content = content
    }

    /// +1 = leading (main moves right), -1 = trailing (main moves left).
    private var direction: CGFloat { edge == .leading ? 1 : -1 }

    private enum DragOwner {
        case drawer
        case content
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
                        .scrollDisabled(dragOwner == .drawer)
                        .allowsHitTesting(!suppressContentInteraction)
                        .clipShape(RoundedRectangle(cornerRadius: 56, style: .continuous))
                        .ignoresSafeArea()

                    // Tap/drag-to-close catcher. Lives inside the offset stack, so
                    // it only covers the main page and never blocks the menu.
                    if p > 0.01 {
                        Color.clear
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !suppressContentInteraction else { return }
                                animate(to: 0)
                            }
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
                if dragOwner == nil {
                    dragOwner = owner(for: value)
                }
                guard dragOwner == .drawer else { return }

                suppressContentInteraction = true

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
                    let didDragDrawer = dragOwner == .drawer
                    edgeDragAccepted = nil
                    dragStartProgress = nil
                    dragOwner = nil
                    if didDragDrawer {
                        releaseContentInteractionSuppression()
                    }
                }
                guard edgeDragAccepted == true, dragOwner == .drawer else { return }

                let base = dragStartProgress ?? progress
                let predicted = base + direction * value.predictedEndTranslation.width / menuWidth
                animate(to: predicted > 0.5 ? 1 : 0)
            }
    }

    private func owner(for value: DragGesture.Value) -> DragOwner? {
        let horizontal = abs(value.translation.width)
        let vertical = abs(value.translation.height)
        let minimumDistance: CGFloat = 10

        guard max(horizontal, vertical) >= minimumDistance else { return nil }
        guard horizontal > vertical * 1.2 else { return .content }
        guard isDrawerDragDirection(value) else { return .content }
        return .drawer
    }

    private func isDrawerDragDirection(_ value: DragGesture.Value) -> Bool {
        if progress <= 0.01 {
            return direction * value.translation.width > 0
        }

        return direction * value.translation.width < 0
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

    private func releaseContentInteractionSuppression() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            suppressContentInteraction = false
        }
    }
}

#if DEBUG
private struct SideDrawerContainerPreview: View {
    @State private var isMenuOpen = false
    @State private var isBackgroundBlack = false

    var body: some View {
        SideDrawerContainer(
            isOpen: $isMenuOpen,
            menu: {
                SideDrawerPreviewMenu(isMenuOpen: $isMenuOpen)
            },
            content: {
                SideDrawerPreviewContent(
                    isMenuOpen: $isMenuOpen,
                    isBackgroundBlack: $isBackgroundBlack
                )
            }
        )
    }
}

private struct SideDrawerPreviewMenu: View {
    @Binding var isMenuOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }

            Text("Menu")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Button("Toggle Drawer") {
                isMenuOpen.toggle()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.25))
            .foregroundStyle(.white)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 60)
        .background(Color.orange.ignoresSafeArea())
    }
}

private struct SideDrawerPreviewContent: View {
    @Binding var isMenuOpen: Bool
    @Binding var isBackgroundBlack: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    isMenuOpen.toggle()
                } label: {
                    Label("Open Drawer", systemImage: "line.3.horizontal")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)

                Text("Scrollable Main Content")
                    .font(.largeTitle.bold())

                ForEach(1...24, id: \.self) { index in
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.cyan.opacity(0.25))
                            .frame(width: 56, height: 56)
                            .overlay {
                                Text("\(index)")
                                    .font(.headline)
                                    .foregroundStyle(.cyan)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scroll and Tap")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(isBackgroundBlack ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onTapGesture {
                        isBackgroundBlack.toggle()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 72)
            .padding(.bottom, 32)
        }
        .background(Color.cyan.opacity(0.5).ignoresSafeArea())
    }
}

#Preview {
    SideDrawerContainerPreview()
}
#endif
