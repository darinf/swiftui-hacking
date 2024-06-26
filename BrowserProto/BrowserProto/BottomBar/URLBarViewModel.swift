import Foundation
import Combine

final class URLBarViewModel {
    @Published var displayText: String = ""
    @Published var editing: Bool = false
}
