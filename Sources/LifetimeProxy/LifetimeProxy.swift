import Foundation
import Observation

import TaskScheduler

/// This class creates a `TaskScheduler` with a run context that will last until the `LifetimeProxy` instance is deinitialized.
///
/// The intention is that this class should be used to act as a proxy for the lifetime of a `Subject` instance, and the subject can use the provided `TaskScheduler` to schedule run context tasks that will be cancelled automatically when the proxy is deinitialized. For this to work as intended, it's important that no additional references to the subject are held, all references should be indirect via the `LifetimeProxy` instance, otherwise the subject could outlive the proxy.
///
/// A `LifetimeProxy` instance can be instantiated as in the example below, with the initializer accepting a non-escaping closure with which the caller can instantiate the `Subject` instance and pass it a reference to the `TaskScheduler`. This closure will only be invoked once during the initialization of the `LifetimeProxy` instance.
/// ```
/// @ObservationIgnored
/// private(set) lazy var fooViewModel: LifetimeProxy<FooViewModel> = LifetimeProxy {
///     FooViewModel(
///         taskScheduler: $0,
///         navigationDelegate: self
///     )
/// }
/// ```
///
/// Once the last reference to the `LifetimeProxy` instance is released, then the run context for the `TaskScheduler` will be cancelled, and this cancellation will propagate to any in-progress run context tasks.
@MainActor
@Observable
public final class LifetimeProxy<Subject: AnyObject & Observable & Sendable> {
    public nonisolated let subject: Subject

    @ObservationIgnored
    fileprivate let taskScheduler: TaskScheduler

    @ObservationIgnored
    private let lifetimeTask: Task<Void, Never>

    public init(
        lifetimeTaskPriority: TaskPriority? = .userInitiated,
        subject: (_ taskScheduler: RunContextTaskSchedulerProtocol) -> Subject
    ) {
        let taskScheduler = TaskScheduler()
        self.subject = subject(taskScheduler)
        self.taskScheduler = taskScheduler
        self.lifetimeTask = Task(priority: lifetimeTaskPriority) { [taskScheduler] in
            await taskScheduler.run()
        }
    }

    deinit {
        lifetimeTask.cancel()

#if DEBUG
        /// Rough debug check to ensure that the subject does not outlive the lifetime of the proxy. Note that this check is not failproof, and may produce false positives (e.g. if an ongoing `Task` is holding a reference to `subject`).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak subject] in
            if let subject {
                assertionFailure("\"\(subject)\" outlived its `LifetimeProxy` instance.")
            }
        }
#endif
    }
}
