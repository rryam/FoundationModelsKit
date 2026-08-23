import Foundation

/// An app-supplied runtime route used by ``FoundationModelExecutionCoordinator``.
public struct FoundationModelExecutionRoute<Request: Sendable, Output: Sendable>: Sendable {
    public typealias RequestPreparation = @Sendable (
        _ request: Request,
        _ transition: FoundationModelRouteTransition
    ) async throws -> Request
    public typealias Execution = @Sendable (_ request: Request) async throws -> Output

    public let runtime: FoundationModelRuntime

    private let requestPreparation: RequestPreparation
    private let execution: Execution

    /// Creates a route. `prepareForFallback` always runs before a request crosses runtimes.
    ///
    /// Stateful callers should use it to rebuild or compact a transcript for the destination
    /// runtime. Stateless requests can use the default identity preparation.
    public init(
        runtime: FoundationModelRuntime,
        prepareForFallback: @escaping RequestPreparation = { request, _ in request },
        execute: @escaping Execution
    ) {
        self.runtime = runtime
        self.requestPreparation = prepareForFallback
        self.execution = execute
    }

    func prepare(
        _ request: Request,
        for transition: FoundationModelRouteTransition
    ) async throws -> Request {
        try await requestPreparation(request, transition)
    }

    func execute(_ request: Request) async throws -> Output {
        try await execution(request)
    }
}
