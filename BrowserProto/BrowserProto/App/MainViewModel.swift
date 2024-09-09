import Combine
import Foundation
import IdentifiedCollections
import UIKit

final class MainViewModel {
    let urlInputViewModel = URLInputViewModel()
    let bottomBarViewModel = BottomBarViewModel()
    let webContentViewModel = WebContentViewModel()
    let cardGridViewModel = CardGridViewModel()
    let tabsModel = TabsModel()
    let tabsStorage = TabsStorage()
    let webContentCache = WebContentCache()

    @Published var suppressInteraction: Bool = false
}

extension MainViewModel {
    var currentTabsSection: TabsSection {
        webContentViewModel.incognito ? .incognito : .default
    }

    func loadData() {
        tabsStorage.loadTabsData { [self] tabsData in
            guard let tabsData else {
                webContentViewModel.openWebContent()
                webContentViewModel.navigate(to: .init(string: "https://news.ycombinator.com/"))
                return
            }
            tabsModel.replaceAllTabsData(tabsData)

            if tabsModel.selectedTabID(inSection: currentTabsSection) == nil {
                cardGridViewModel.showGrid = true
            }
        }
    }

    func updateCardGrid(for change: TabsModel.TabsChange, in section: TabsSection) {
        guard currentTabsSection == section else { return }
        switch change {
        case let .selected(tabID):
            cardGridViewModel.selectedID = tabID
        case let .appended(tab):
            cardGridViewModel.appendCard(.init(from: tab))
        case let .inserted(tab, atIndex: index):
            cardGridViewModel.insertCard(.init(from: tab), atIndex: index)
        case let .removed(atIndex: index):
            cardGridViewModel.removeCard(atIndex: index)
        case .removedAll:
            cardGridViewModel.removeAllCards()
        case let .updated(field, atIndex: index):
            switch field {
            case let .title(title):
                cardGridViewModel.updateTitle(title, forCardAtIndex: index)
            case let .favicon(favicon):
                cardGridViewModel.updateFavicon(favicon?.image, forCardAtIndex: index)
            case let .thumbnail(thumbnail):
                cardGridViewModel.updateThumbnail(thumbnail?.image, forCardAtIndex: index)
            case .url, .interactionState, .lastAccessedTime:
                break
            }
        case let .updatedAll(tabsSectionData):
            cardGridViewModel.replaceAllCards(
                .init(uniqueElements: tabsSectionData.tabs.map { Card(from: $0) }),
                selectedID: tabsSectionData.selectedTabID
            )
        case let .swapped(atIndex1: index1, atIndex2: index2):
            cardGridViewModel.swapCards(atIndex1: index1, atIndex2: index2)
        }
    }

    func updateTabs(for change: WebContentViewModel.WebContentChange) {
        let currentWebContent = webContentViewModel.webContent
        switch change {
        case let .opened(relativeToOpener):
            let newTab = TabData(from: currentWebContent!)
            if relativeToOpener, let opener = currentWebContent!.opener {
                tabsModel.insertTab(newTab, inSection: currentTabsSection, after: opener.id)
            } else {
                tabsModel.appendTab(newTab, inSection: currentTabsSection)
            }
            currentWebContent.map { webContentCache.insert($0) }
        case .switched:
            currentWebContent.map { webContentCache.insert($0) }
        case let .poppedBack(from: closedWebContent):
            tabsModel.selectTab(byID: currentWebContent?.id, inSection: currentTabsSection)
            tabsModel.removeTab(byID: closedWebContent.id, inSection: currentTabsSection)
            webContentCache.remove(closedWebContent)
            // TODO: If currentWebContent is nil, then we need to select a different card.
        }
        tabsModel.selectTab(byID: currentWebContent?.id, inSection: currentTabsSection)
    }

    func updateSelectedTabLastAccessedTime() {
        guard let tabID = tabsModel.selectedTabID(inSection: currentTabsSection) else { return }
        tabsModel.update(.lastAccessedTime(.now), forTabByID: tabID, inSection: currentTabsSection)
    }

    func updateSelectedTabThumbnailIfShowing(completion: @escaping () -> Void) {
        if !cardGridViewModel.showGrid, let webContent = webContentViewModel.webContent {
            suppressInteraction = true
            // updateThumbnail could be blocked on a network load of the initial page. In that
            // case, we need to timeout.
            var timedOut = false
            var completed = false
            webContent.updateThumbnail { [self] in
                guard !timedOut else { return }
                suppressInteraction = false
                completed = true
                completion()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) { [self] in
                guard !completed else { return }
                timedOut = true
                suppressInteraction = false
                completion()
            }
        } else {
            Task { @MainActor in
                completion()
            }
        }
    }

    func validateOpener() {
        if let opener = webContentViewModel.webContent?.opener,
           !tabsModel.tabExists(byID: opener.id, inSection: currentTabsSection) {
            webContentViewModel.webContent?.dropOpener()
        }
    }

    private func setIncognito(incognito: Bool) {
        webContentViewModel.incognito = incognito

        var cards = IdentifiedArrayOf<Card>()
        tabsModel.data.sections[id: currentTabsSection]!.tabs.forEach { tab in
            cards.append(.init(from: tab))
        }
        let selectedID = tabsModel.data.sections[id: currentTabsSection]!.selectedTabID
        cardGridViewModel.replaceAllCards(cards, selectedID: selectedID)
        if cards.isEmpty {
            cardGridViewModel.showGrid = true
        }
    }
}

extension MainViewModel {
    func handle(_ action: URLInputView.Action) {
        switch action {
        case let .navigate(text, target):
            if case .newTab = target {
                let currentWebContent = webContentViewModel.webContent
                webContentViewModel.openWebContent(withOpener: currentWebContent, relativeToOpener: false)
            }
            webContentViewModel.navigate(to: URLInput.url(from: text))
            if cardGridViewModel.showGrid {
                UIView.performWithoutAnimation { [self] in
                    cardGridViewModel.showGrid = false
                }
            }
        }
    }

    func handle(_ action: CardGridView.Action) {
        switch action {
        case let .removeCard(byID: cardID):
            tabsModel.removeTab(byID: cardID, inSection: currentTabsSection)
        case let .selectCard(byID: cardID):
            tabsModel.selectTab(byID: cardID, inSection: currentTabsSection)
            cardGridViewModel.showGrid = false
            updateSelectedTabLastAccessedTime()
        case let .swappedCards(index1, index2):
            tabsModel.swapTabs(inSection: currentTabsSection, atIndex1: index1, atIndex2: index2)
        }
    }

    func handle(_ action: BottomBarView.Action) {
        switch action {
        case .editURL:
            urlInputViewModel.visibility = .showing(
                initialValue: webContentViewModel.url?.absoluteString ?? "",
                forTarget: .currentTab
            )
        case .goBack:
            webContentViewModel.goBack()
        case .goForward:
            webContentViewModel.goForward()
        case .showTabs:
            updateSelectedTabLastAccessedTime()
            updateSelectedTabThumbnailIfShowing() { [self] in
                cardGridViewModel.showGrid.toggle()
            }
        case .addTab:
            urlInputViewModel.visibility = .showing(initialValue: "", forTarget: .newTab)
        case .mainMenu(let mainMenuAction):
            print(">>> mainMenu: \(mainMenuAction)")
            switch mainMenuAction {
            case .toggleIncognito(let incognitoEnabled):
                updateSelectedTabLastAccessedTime()
                updateSelectedTabThumbnailIfShowing() { [self] in
                    setIncognito(incognito: incognitoEnabled)
                    updateSelectedTabLastAccessedTime()
                }
            }
        }
    }
}

extension Card {
    init(from tab: TabData) {
        self.init(
            id: tab.id,
            title: tab.title,
            favicon: tab.favicon?.image,
            thumbnail: tab.thumbnail?.image
        )
    }
}

extension TabData {
    init(from webContent: WebContent) {
        self.init(
            id: webContent.id,
            url: webContent.url,
            title: webContent.title,
            favicon: webContent.favicon,
            thumbnail: webContent.thumbnail
        )
    }
}
