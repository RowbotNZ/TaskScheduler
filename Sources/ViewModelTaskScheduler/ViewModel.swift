import Observation
import SwiftUI

@MainActor
public protocol ViewModel: Observable {
    associatedtype ViewType: View

    func buildView() -> ViewType
}
