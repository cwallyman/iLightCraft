//
//  AdjustmentPanel.swift
//  Unveil
//

import SwiftUI

/// AdjustmentPanel is one page of the adjust card: the group's title as its own header and the
/// sliders below it. It turns each slider gesture into the view model's calls.
///
/// The page hugs its rows (`RowsHeight`), so the card is only as tall as its content; only when
/// the rows do not fit (a short window, a large Dynamic Type size) do they scroll. There is one
/// copy of the rows: a `ViewThatFits` with and without a scroll view would keep two, and the
/// hidden one re-evaluated every row on every drag tick. The scroll view is disabled while a
/// slider drags: precision bands ask the finger to move vertically, and that must never scroll
/// the page. The sliders stay disabled until a photo is open (there is nothing for the engine to
/// apply them to) and while the canvas shows the unedited look, so no edit lands unseen.
///
/// Each row is `.equatable()`, and the panel hands it its value as a plain number, so a drag
/// re-evaluates the panels (cheap) and the dragged row only, not every row on every page.
///
/// Calls start with `Task.immediate`, so each runs its synchronous part (clamp, record, queue)
/// right away, in the order SwiftUI delivered the values. A plain `Task` would only be scheduled,
/// and the release could then queue its full preview ahead of the last drag value.
struct AdjustmentPanel<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>
    let group    : AdjustmentGroup
    var isCompact: Bool = false

    @State
    private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if !isCompact {
                Text(group.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            }

            RowsHeight {
                ScrollView {
                    rows
                }
                .scrollDisabled(isDragging)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .disabled(!viewModel.isPhotoOpen || viewModel.isShowingBefore)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 16) {

            ForEach(group.kinds, id: \.self) { kind in
                AdjustmentSlider(
                    kind             : kind,
                    value            : viewModel.values[kind] ?? kind.defaultValue,
                    defaultValue     : viewModel.defaultValue(of: kind),
                    onDragValue      : { drag(kind, to: $0) },
                    onEditingChanged : { editingChanged(kind, isEditing: $0) },
                    onCommit         : { commit(kind, to: $0) },
                    onNudge          : { nudge(kind, by: $0) },
                    onReset          : { Task.immediate { await viewModel.reset(kind) } },
                    isCompact        : isCompact
                )
                .equatable()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, isCompact ? 8 : 0)
    }

    /// drag sends one new slider value of a drag in progress.
    private func drag(
        _ kind     : DevelopAdjustmentKind,
        to newValue: Double
    ) {
        Task.immediate { await viewModel.drag(kind, to: newValue) }
    }

    /// commit runs one whole edit (a typed value, a VoiceOver step): begin, set the value, end
    /// with a full preview. Each one is final, so it must not stop on a draft frame.
    private func commit(
        _ kind     : DevelopAdjustmentKind,
        to newValue: Double
    ) {
        Task.immediate {
            viewModel.beginDrag(kind)
            await viewModel.drag(kind, to: newValue)
            await viewModel.endDrag(kind)
        }
    }

    private func nudge(
        _ kind  : DevelopAdjustmentKind,
        by delta: Double
    ) {
        Task.immediate { await viewModel.nudge(kind, by: delta) }
    }

    private func editingChanged(
        _ kind   : DevelopAdjustmentKind,
        isEditing: Bool
    ) {
        isDragging = isEditing

        if isEditing {
            viewModel.beginDrag(kind)
        } else {
            Task.immediate { await viewModel.endDrag(kind) }
        }
    }
}

/// RowsHeight sizes the page's scroll view to its rows, up to the height it is offered. A
/// ScrollView alone takes all the height it gets; its ideal height is its content's, so asking
/// for that and clamping it to the offer makes the page hug its rows and scroll only past it.
private struct RowsHeight: Layout {

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache   : inout ()
    ) -> CGSize {
        guard let content = subviews.first else { return .zero }

        let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))

        return CGSize(width: ideal.width, height: min(ideal.height, proposal.height ?? ideal.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal : ProposedViewSize,
        subviews : Subviews,
        cache    : inout ()
    ) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
