import Foundation

/// An app or package error that exposes a stable Foundation Models error projection.
public protocol FoundationModelProjectedError: Error, Sendable {
    var foundationModelErrorProjection: FoundationModelErrorProjection { get }
}
