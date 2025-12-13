import Observation
import SwiftUI

import TaskScheduler

@MainActor
@Observable
public final class ViewModelHolder<ViewModel: Observable> {
    public let viewModel: ViewModel

    @ObservationIgnored
    fileprivate let viewModelTaskScheduler: ViewModelTaskScheduler

    @ObservationIgnored
    private let lifetimeTask: Task<Void, Never>

    public init(
        viewModel: (_ viewModelTaskScheduler: ViewModelTaskSchedulerProtocol) -> ViewModel
    ) {
        let viewModelTaskScheduler = ViewModelTaskScheduler()
        self.viewModel = viewModel(viewModelTaskScheduler)
        self.viewModelTaskScheduler = viewModelTaskScheduler
        self.lifetimeTask = Task { [viewModelTaskScheduler] in
            await viewModelTaskScheduler.runLifetimeContext()
        }
    }

    deinit {
        /// It's important to note that our view model may have enqueued some on-screen tasks while there was not an active on-screen run context. To make sure that these tasks get the chance to execute, we create a final on-screen run context and immediately cancel it.
        Task { [viewModelTaskScheduler] in
            await viewModelTaskScheduler.runOnScreenContext()
        }.cancel()

        lifetimeTask.cancel()
    }
}

@MainActor
public protocol ViewModelTaskSchedulerProtocol {
    /// Schedule a task to be coupled to the "on-screen" state of the view model. If the view model goes off-screen then tasks scheduled in this way will be cancelled.
    func onScreenTask(_ task: @escaping @Sendable () async -> Void)

    /// Schedule a task to be coupled to the lifetime of the view model. The task will be cancelled when the view model holder is deinitialized.
    func lifetimeTask(_ task: @escaping @Sendable () async -> Void)

    /// Schedule a regular unstructured `Task`.
    @discardableResult
    nonisolated func task(
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never>
}

@MainActor
final class ViewModelTaskScheduler: ViewModelTaskSchedulerProtocol {
    private let onScreenTaskScheduler: TaskScheduler = TaskScheduler()

    private let lifetimeTaskScheduler: TaskScheduler = TaskScheduler()

    private let taskCompletionStream: AsyncStream<Void>

    private let taskCompletionStreamContinuation: AsyncStream<Void>.Continuation

    init() {
        let (taskCompletionStream, taskCompletionStreamContinuation) = AsyncStream<Void>.makeStream()
        self.taskCompletionStream = taskCompletionStream
        self.taskCompletionStreamContinuation = taskCompletionStreamContinuation
    }

    func runOnScreenContext() async {
        await onScreenTaskScheduler.run()
    }

    func runLifetimeContext() async {
        await lifetimeTaskScheduler.run()
    }

    func onScreenTask(_ task: @escaping @Sendable () async -> Void) {
        onScreenTaskScheduler.addRunContextTask { [self] in
            await task()

            taskCompletionStreamContinuation.yield()
        }
    }

    func lifetimeTask(_ task: @escaping @Sendable () async -> Void) {
        lifetimeTaskScheduler.addRunContextTask { [self] in
            await task()

            taskCompletionStreamContinuation.yield()
        }
    }

    @discardableResult
    nonisolated func task(
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task {
            await task()

            taskCompletionStreamContinuation.yield()
        }
    }
}

public struct ViewModelView<ViewModelType: ViewModel>: View {
    public var body: some View {
        viewModelHolder.viewModel.buildView()
            .task {
                await viewModelHolder.viewModelTaskScheduler.runOnScreenContext()
            }
    }

    @State
    public var viewModelHolder: ViewModelHolder<ViewModelType>

    public init(viewModelHolder: ViewModelHolder<ViewModelType>) {
        self.viewModelHolder = viewModelHolder
    }
}

// MARK: - Test Utilities

extension ViewModelTaskScheduler {
    /// Waits for the next completion of a scheduled async task, or until the timeout duration has elapsed (in which case an error is thrown).
    func next(timeout: TimeInterval = 10) async throws {
        try await Task.detached { [taskCompletionStream] in
            try await withThrowingTaskGroup(of: Void.self) { @MainActor [taskCompletionStream] taskGroup in
                taskGroup.addTask { [taskCompletionStream] in
                    for await _ in taskCompletionStream {
                        return
                    }

                    throw CancellationError()
                }

                taskGroup.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * Double(NSEC_PER_SEC)))

                    throw CancellationError()
                }

                try await taskGroup.next()

                taskGroup.cancelAll()
            }
        }.value
    }
}
