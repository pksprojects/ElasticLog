

import ElasticNIOClient
import Foundation
import Logging
import NIO
import NIOSSL

// MARK: - ElasticLogSystem

public enum ElasticLogSystem {
    fileprivate static var logLevelOverrides: [String: Logger.Level] = [:]
    fileprivate static var logLevel: Logger.Level = .info

    public static func bootstrapFactory(with settings: Settings) throws -> ((String) -> LogHandler) {
        ElasticLogSystem.logLevelOverrides = settings.logLevelOverrides
        ElasticLogSystem.logLevel = settings.logLevel

        let appenders = try settings.appenderSettings.map { appSet throws -> ElasticLogAppender in
            try appSet.appender.init(appSet)
        }

        return { label in
            ElasticLogHandler(label: label, appenders: appenders, handlerFactories: settings.handlerFactories, logEncoder: settings.logEncoder)
        }
    }

    public static func bootstrapSwiftLog(with settings: Settings) throws {
        LoggingSystem.bootstrap(try bootstrapFactory(with: settings))
    }

    public static subscript(logLevelOverrideKey key: String) -> Logger.Level? {
        get {
            return ElasticLogSystem.logLevelOverrides[key]
        }
        set(newValue) {
            ElasticLogSystem.logLevelOverrides[key] = newValue
        }
    }
}

extension ElasticLogSystem {
    public struct Settings {
        public let logLevel: Logger.Level
        public let appenderSettings: [LogAppenderSettings]
        public let handlerFactories: [(String) -> LogHandler]
        public var logEncoder: LogEntryEncoder
        public var logLevelOverrides: [String: Logger.Level]

        public init(logLevel: Logger.Level, appenderSettings: [LogAppenderSettings], handlerFactories: [(String) -> LogHandler] = [], logEncoder: LogEntryEncoder = JsonLogEntryEncoder(), logLevelOverrides: [String: Logger.Level] = [:]) {
            self.logLevel = logLevel
            self.appenderSettings = appenderSettings
            self.handlerFactories = handlerFactories
            self.logEncoder = logEncoder
            self.logLevelOverrides = logLevelOverrides
        }
    }

    public enum DateEncodingStrategy {
        /// Encode the `Date` as a UNIX timestamp (as a JSON number).
        case secondsSince1970

        /// Encode the `Date` as UNIX millisecond timestamp (as a JSON number).
        case millisecondsSince1970

        /// Encode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        case iso8601

        /// Encode the `Date` as a string formatted by the given formatter.
        case formatted(DateFormatter)
    }
}

// MARK: - ElasticLogHandler

public struct ElasticLogHandler: LogHandler {
    public var metadata = Logger.Metadata()

    public var logLevel: Logger.Level {
        get {
            if let level = ElasticLogSystem.logLevelOverrides[self.label] {
                return level
            } else {
                return ElasticLogSystem.logLevel
            }
        }
        set(newValue) {
            ElasticLogSystem.logLevelOverrides[self.label] = newValue
        }
    }

    public let appenders: [ElasticLogAppender]

    public let logHandlers: [LogHandler]

    public let label: String

    private let logEncoder: LogEntryEncoder

    public init(label: String, appenders: [ElasticLogAppender], handlerFactories: [(String) -> LogHandler], logEncoder: LogEntryEncoder) {
        self.label = label
        self.appenders = appenders
        logHandlers = handlerFactories.map { $0(label) }
        self.logEncoder = logEncoder
    }

    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        let combinedMetaData = self.metadata.merging(metadata ?? [:]) { current, _ in current }
        let logEntry: LogEntry = .init(timestamp: Date(), level: level, metaData: combinedMetaData, message: message, line: line, file: file, function: function, label: label)
        let data = try? logEncoder.encode(logEntry)
        precondition(data != nil, "Unable to convert log to data")
        appenders.forEach { appender in
            appender.execute(data!).whenComplete { result in
                switch result {
                case let .failure(error):
                    print("Error while writing logs to socket; LogData: \(String(data: data!, encoding: .utf8) ?? "Unable to decode LogData to string"); Error: \(error)")
                case .success:
                    return
                }
            }
        }
        logHandlers.forEach { handler in
            handler.log(level: level, message: message, metadata: metadata, file: file, function: function, line: line)
        }
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            return metadata[key]
        }
        set(newValue) {
            metadata[key] = newValue
        }
    }
}

// MARK: - LogEntry

public struct LogEntry: Codable, Equatable {
    public let timestamp: Date
    public let level: Logger.Level
    public let metaData: Logger.Metadata
    public let message: Logger.Message
    public let line: UInt
    public let file: String
    public let function: String
    public let label: String

    enum CodingKeys: String, CodingKey {
        case timestamp = "@timestamp"
        case level
        case metaData
        case message
        case line
        case file
        case function
        case label
    }
}

extension LogEntry {
    public var prettyMetadata: String {
        return prettify(metaData)
    }

    private func prettify(_ metadata: Logger.Metadata) -> String {
        return !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : ""
    }
}

// MARK: - LogEntryEncoder

public protocol LogEntryEncoder {
    func encode(_ logEntry: LogEntry) throws -> Data
}

public class JsonLogEntryEncoder: LogEntryEncoder {
    public let encoder: JSONEncoder

    public static var defaultEncoder: JSONEncoder {
        let jsonEncoder = JSONEncoder()
        if #available(OSX 10.12, *) {
            jsonEncoder.dateEncodingStrategy = .iso8601
        } else {
            // Fallback on earlier versions
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            jsonEncoder.dateEncodingStrategy = .formatted(dateFormatter)
        }
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        return jsonEncoder
    }

    public init(_ encoder: JSONEncoder = JsonLogEntryEncoder.defaultEncoder) {
        self.encoder = encoder
    }

    public func encode(_ logEntry: LogEntry) throws -> Data {
        return try encoder.encode(logEntry)
    }
}

public class StringLogEntryEncoder: LogEntryEncoder {
    public let dateEncodingStrategy: ElasticLogSystem.DateEncodingStrategy

    private let iso8601DateFormatter: DateFormatter

    public init(dateEncodingStrategy: ElasticLogSystem.DateEncodingStrategy = .iso8601) {
        self.dateEncodingStrategy = dateEncodingStrategy
        iso8601DateFormatter = DateFormatter()
        iso8601DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        iso8601DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    }

    public func encode(_ logEntry: LogEntry) throws -> Data {
        return "\(formatTimestamp(date: logEntry.timestamp)) \(logEntry.level) \(logEntry.label): \(logEntry.prettyMetadata) \(logEntry.message)".data(using: .utf8)!
    }

    private func formatTimestamp(date: Date) -> String {
        let date = Date()
        switch dateEncodingStrategy {
        case .millisecondsSince1970:
            return "\(date.timeIntervalSince1970)"
        case .secondsSince1970:
            return "\(date.timeIntervalSince1970 / 1000)"
        case let .formatted(formatter):
            return formatter.string(from: date)
        case .iso8601:
            return iso8601DateFormatter.string(from: date)
        }
    }
}

// MARK: - Utility Extensions

extension Logger.Message: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        self = Logger.Message(stringLiteral: string)
    }
}

extension Logger.MetadataValue: Codable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .array(value):
            var container = encoder.unkeyedContainer()
            try container.encode(value)
        case let .dictionary(dic):
            var container = encoder.singleValueContainer()
            try container.encode(dic)
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .stringConvertible(value):
            var container = encoder.singleValueContainer()
            try container.encode(value.description)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([Logger.MetadataValue].self) {
            self = .array(arr)
        } else {
            let dic = try container.decode([String: Logger.MetadataValue].self)
            let val: Logger.Metadata = dic
            self = .dictionary(val)
        }
    }
}
