import Foundation

public protocol TaskSchedulerProtocol {
    /// Wraps a unit of asynchronous work in a `Task` and returns the `Task`.
    @discardableResult
    func task(
        priority: TaskPriority?,
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never>

    /// Wraps a unit of asynchronous work in a "detached" `Task` and returns the `Task`.
    @discardableResult
    func detachedTask(
        priority: TaskPriority?,
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never>
}

public protocol RunContextTaskSchedulerProtocol: TaskSchedulerProtocol {
    /// Adds a unit of asynchronous work to the run context, if it is active, otherwise adds it to a queue to be scheduled when the run context is established.
    @MainActor
    func runContextTask(_ task: @escaping @Sendable () async -> Void)
}

extension TaskSchedulerProtocol {
    @discardableResult
    public func task(
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        self.task(priority: nil, task)
    }

    @discardableResult
    public func detachedTask(
        _ task: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        detachedTask(priority: nil, task)
    }
}

extension TaskScheduler: RunContextTaskSchedulerProtocol {}
