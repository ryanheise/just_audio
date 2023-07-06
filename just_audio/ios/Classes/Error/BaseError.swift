//
//  BaseError.swift
//  kMusicSwift
//
//  Created by kuama on 29/08/22.
//

import Foundation

/**
 * Base class for errors
 */
open class BaseError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    open var baseDescription: String { "\(type(of: self))" }

    /// The error description
    public var description: String {
        var description = baseDescription

        if let message = message {
            description += ": " + message
        }

        if let cause = cause {
            description += ", cause: \(cause)"
        }

        return description
    }

    /// The debug description
    public var debugDescription: String {
        var description = baseDescription

        if let message = message {
            description += ": " + message
        }

        if let cause = cause {
            description += ", cause: \(String(reflecting: cause))"
        }

        return description
    }

    /// The error message
    public let message: String?
    /// The error cause
    public let cause: Error?

    /**
     * Initialize `BaseError`
     *
     * - Parameter message: the error message.
     * - Parameter cause: the error cause.
     */
    public init(message: String? = nil, cause: Error? = nil) {
        self.message = message
        self.cause = cause
    }

    /**
     * Forces a cast to `BaseError`
     *
     * - Parameter error: the given error.
     */
    public static func fromError(_ error: Error) -> Self {
        guard let convertedError = error as? Self else {
            fatalError("Cannot force-convert \(error.self) to \(self))")
        }
        return convertedError
    }
}
