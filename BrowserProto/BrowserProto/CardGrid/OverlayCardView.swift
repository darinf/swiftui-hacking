import Combine
import UIKit

final class OverlayCardView: UIView {
    private let model: OverlayCardViewModel
    private let zoomedView: UIView
    private var cardView: CardView?
    private var cardViewModel: CardViewModel?
    private var cardViewRect: CGRect?
    private var subscriptions: Set<AnyCancellable> = []

    init(model: OverlayCardViewModel, zoomedView: UIView) {
        self.model = model
        self.zoomedView = zoomedView
        super.init(frame: .zero)

        addSubview(zoomedView)

        setupObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        zoomedView.frame = bounds

        if let cardView {
            if let cardViewRect {
                cardView.frame = cardViewRect
            } else {
                cardView.frame = bounds
            }
        }
    }

    private func setupObservers() {
        model.$state.sink { [weak self] state in
            guard let self else { return }
            switch state {
            case .hidden:
                removeCardView()
            case let .transitionToGrid(card: card, cardAt: cardRect):
                transitionToGrid(card: card, cardAt: cardRect)
            case let .transitionToZoomed(card: card, cardAt: cardRect):
                transitionToZoomed(card: card, cardAt: cardRect)
            }
        }.store(in: &subscriptions)
    }

    private func transitionToGrid(card: Card?, cardAt cardRect: CGRect?) {
        let cardViewModel = createCardViewIfNeeded(card: card)

        zoomedView.isHidden = true
        cardViewModel.selected = false
        cardViewModel.hideCloseButton = true
        cardViewModel.disableCornerRadius = true

        layoutIfNeeded()

        cardViewRect = cardRect
        setNeedsLayout()

        UIView.animate(withDuration: 0.3) { [self] in
            cardViewModel.selected = true
            cardViewModel.hideCloseButton = false
            cardViewModel.disableCornerRadius = false
            layoutIfNeeded()
        } completion: { [self] _ in
            guard case .transitionToGrid = model.state else { return }
            isUserInteractionEnabled = false
            model.state = .hidden
        }
    }

    private func transitionToZoomed(card: Card?, cardAt cardRect: CGRect?) {
        let cardViewModel = createCardViewIfNeeded(card: card)

        zoomedView.isHidden = true
        cardViewModel.selected = true
        cardViewModel.hideCloseButton = false
        cardViewModel.disableCornerRadius = false

        cardViewRect = cardRect
        setNeedsLayout()

        layoutIfNeeded()

        cardViewRect = nil
        setNeedsLayout()

        UIView.animate(withDuration: 0.3) { [self] in
            cardViewModel.selected = false
            cardViewModel.hideCloseButton = true
            cardViewModel.disableCornerRadius = true
            layoutIfNeeded()
        } completion: { [self] _ in
            guard case .transitionToZoomed = model.state else { return }
            isUserInteractionEnabled = true
            model.state = .hidden
            zoomedView.isHidden = false
            bringSubviewToFront(zoomedView)
        }
    }

    private func createCardViewIfNeeded(card: Card?) -> CardViewModel {
        if let cardViewModel {
            return cardViewModel
        }

        let cardViewModel = CardViewModel(selected: false, thumbnail: card?.thumbnail, title: card?.title)
        let cardView = CardView(model: cardViewModel)

        self.cardViewModel = cardViewModel
        self.cardView = cardView

        addSubview(cardView)

        return cardViewModel
    }

    private func removeCardView() {
        cardView?.removeFromSuperview()
        cardView = nil
        cardViewModel = nil
        cardViewRect = nil
    }
}
