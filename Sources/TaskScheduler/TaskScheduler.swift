import Combine
import Foundation

/// Can be used as a way of scheduling asynchronous work that is executed within a provided Structured Concurrency scope, referred to as the run context. No scheduled run context work will be executed until `run()` is called to establish a Structured Concurrency scope. If the run context scope is cancelled then all child Tasks will be cancelled along with it. Note that scheduled Tasks can run concurrently.
@MainActor
public final class TaskScheduler: Sendable {
    @Published
    public private(set) var isRunning: Bool = false

    private var runContextTask: Task<Void, Never>?

    private var runContextStream: AsyncStream<Void>? {
        didSet {
            isRunning = runContextStream != nil
        }
    }

    private var runContextStreamContinuation: AsyncStream<Void>.Continuation?

    private let taskCompletionStream: AsyncStream<Void>

    private let taskCompletionStreamContinuation: AsyncStream<Void>.Continuation

    private var queuedRunContextTasks: [@Sendable () async -> Void] = []

    public init() {
        let (taskCompletionStream, taskCompletionStreamContinuation) = AsyncStream<Void>.makeStream()
        self.taskCompletionStream = taskCompletionStream
        self.taskCompletionStreamContinuation = taskCompletionStreamContinuation
    }

    deinit {
        runContextStreamContinuation?.finish()
        taskCompletionStreamContinuation.finish()
    }

    /// Creates the run context for this task scheduler. Work that is added via the `addRunContextTask(_:)` method will be run within this context. This method should not be called again while the task scheduler is running.
    ///
    /// - Parameters:
    ///   - willBegin: An optional callback that will be invoked immediately before the run context is established. This gives callers an opportunity to enqueue any run context tasks which should begin immediately (enqueueing these tasks from anywhere else runs the risk of mistakenly attaching them to the previous run context, if there was one).
    public func run(
        willBegin: (@MainActor @Sendable () -> Void)? = nil
    ) async {
        while runContextTask != nil {
            /// The task scheduler is already running, wait until it is finished before starting a new run context.
            await runContextTask?.value
        }

        let task = Task {
            defer {
                /// If we have reached this point then the parent `Task` must have been cancelled, meaning that the task scheduler is no longer running.
                runContextStream = nil
                runContextStreamContinuation = nil
                runContextTask = nil
            }

            /// Invoke the `willBegin` callback now that the resources for any prior run context have been tidied up.
            willBegin?()

            /// Create task stream resources to iterate run context tasks. These will remain active until the parent task is cancelled.
            let (runContextStream, runContextStreamContinuation) = AsyncStream<Void>.makeStream()
            self.runContextStream = runContextStream
            self.runContextStreamContinuation = runContextStreamContinuation

            let handleTask: @Sendable (@Sendable () async -> Void) async -> Void = { [weak self] task in
                await task()

                self?.taskCompletionStreamContinuation.yield()
            }

            await withTaskGroup(of: Void.self) { [self] taskGroup in
                let handleQueuedRunContextTasks: (inout TaskGroup) -> Void = { [self] taskGroup in
                    while !queuedRunContextTasks.isEmpty {
                        let task = queuedRunContextTasks.removeFirst()

                        taskGroup.addTask {
                            await handleTask(task)
                        }
                    }
                }

                /// Handle any run context tasks that were enqueued before the run context was established.
                handleQueuedRunContextTasks(&taskGroup)

                /// Handle enqueued run context tasks every time `runContextStream` emits an element.
                for await _ in runContextStream {
                    handleQueuedRunContextTasks(&taskGroup)
                }

                /// If the parent task was cancelled while `runContextStream` had elements buffered, the `AsyncStream` will have dropped these elements, so we manually handle all of the remaining tasks at the end. Doing this ensures that every enqueued task gets executed, even if it is immediately cancelled, allowing any tidy up that may be required.
                handleQueuedRunContextTasks(&taskGroup)
            }
        }

        runContextTask = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Adds a unit of asynchronous work to the run context, if it is active, otherwise adds it to a queue to be scheduled when the run context is established.
    public func addRunContextTask(_ task: @escaping @Sendable () async -> Void) {
        queuedRunContextTasks.append(task)

        if let runContextStreamContinuation {
            runContextStreamContinuation.yield()
        }
    }

    /// Wraps a unit of asynchronous work in a `Task` and returns the `Task`. This `Task` is not coupled to the run context.
    @discardableResult
    public nonisolated func task(
        priority: TaskPriority? = nil,
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task(priority: priority) {
            await task()

            taskCompletionStreamContinuation.yield()
        }
    }

    /// Wraps a unit of asynchronous work in a "detached" `Task` and returns the `Task`. This `Task` is not coupled to the run context.
    @discardableResult
    public nonisolated func detachedTask(
        priority: TaskPriority? = nil,
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: priority) { [self] in
            await task()

            taskCompletionStreamContinuation.yield()
        }
    }
}

// MARK: - Test Utilities

extension TaskScheduler {
    /// Waits for the next completion of a scheduled async task, or until the timeout duration has elapsed (in which case an error is thrown).
    public func next(timeout: TimeInterval = 10) async throws {
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
