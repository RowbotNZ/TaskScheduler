import Observation
import SwiftUI

@MainActor
public protocol ViewModel: Observable {
    associatedtype ViewType: View

    func buildView() -> ViewType
}

@MainActor
public protocol TaskSchedulerViewModel: ViewModel {}

@MainActor
public extension TaskSchedulerViewModel {
    public static func buildView(
        viewModel: (_ viewModelTaskScheduler: ViewModelTaskScheduler) -> Self
    ) -> some View {
        ViewModelView<Self>(viewModelHolder: ViewModelHolder<Self>(viewModel: viewModel))
    }
}

@MainActor
@Observable
final class ViewModelHolder<ViewModelType: ViewModel> {
    let viewModel: ViewModelType

    @ObservationIgnored
    fileprivate let viewModelTaskScheduler: ViewModelTaskScheduler

    @ObservationIgnored
    private let lifetimeTask: Task<Void, Never>

    init(
        viewModel: (_ viewModelTaskScheduler: ViewModelTaskScheduler) -> ViewModelType
    ) {
        let viewModelTaskScheduler = ViewModelTaskSchedulerImplementation()
        self.viewModel = viewModel(viewModelTaskScheduler)
        self.viewModelTaskScheduler = viewModelTaskScheduler
        self.lifetimeTask = Task { [viewModelTaskScheduler] in
            await viewModelTaskScheduler.run()
        }
    }

    deinit {
        lifetimeTask.cancel()
    }
}

struct ViewModelView<ViewModelType: ViewModel>: View {
    var body: some View {
        viewModelHolder.viewModel.buildView()
    }

    @State
    var viewModelHolder: ViewModelHolder<ViewModelType>

    init(viewModelHolder: ViewModelHolder<ViewModelType>) {
        self.viewModelHolder = viewModelHolder
    }
}
