import Observation
import SwiftUI

import TaskScheduler

@MainActor
public protocol ViewModelTaskScheduler {
    /// Schedule a task to be coupled to the lifetime of the view model. The task will be cancelled when the view model holder is deinitialized.
    func lifetimeTask(_ task: @escaping @Sendable () async -> Void)

    /// Schedule a regular unstructured `Task`.
    @discardableResult
    nonisolated func task(
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never>
}

@MainActor
final class ViewModelTaskSchedulerImplementation: ViewModelTaskScheduler {
    private let taskScheduler: TaskScheduler = TaskScheduler()

    private let taskCompletionStream: AsyncStream<Void>

    private let taskCompletionStreamContinuation: AsyncStream<Void>.Continuation

    init() {
        let (taskCompletionStream, taskCompletionStreamContinuation) = AsyncStream<Void>.makeStream()
        self.taskCompletionStream = taskCompletionStream
        self.taskCompletionStreamContinuation = taskCompletionStreamContinuation
    }

    func run() async {
        await taskScheduler.run()
    }

    func lifetimeTask(_ task: @escaping @Sendable () async -> Void) {
        taskScheduler.addRunContextTask { [self] in
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

// MARK: - Test Utilities

extension ViewModelTaskSchedulerImplementation {
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
