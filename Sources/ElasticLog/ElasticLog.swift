

import Foundation
import Logging
import NIO
import NIOSSL

// MARK:- ElasticLogSystem

public enum ElasticLogSystem {
    
    fileprivate static var logLevelOverrides: [String: Logger.Level] = [:]
    fileprivate static var logLevel: Logger.Level = .info
    
    public static func bootstrapFactory(with setting: Settings) throws -> ((String) -> LogHandler) {
        
        var sslContext: NIOSSLContext? = nil
        
        if setting.useSSL && setting.tlsConfig == nil {
            let tlsConfig = TLSConfiguration.clientDefault
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        } else if let tlsConfig = setting.tlsConfig {
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        }
        let client = TCPClient(setting.host, port: setting.port, eventLoopProvider: setting.eventLoopProvider, sslContext: sslContext)
        ElasticLogSystem.logLevelOverrides = setting.logLevelOverrides
        ElasticLogSystem.logLevel = setting.logLevel
        return { label in
            return ElasticLogHandler(label: label, tcpClient: client)
        }
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
        
        public let host: String
        public let port: Int
        public var useSSL: Bool = false
        public var tlsConfig: TLSConfiguration? = nil
        public var outputMode: OutputMode = .json
        public var eventLoopProvider: EventLoopProvider = .createNew(threads: 1)
        public var logLevel: Logger.Level = .info
        public var logLevelOverrides: [String: Logger.Level] = [:]
        
    }
    
    public enum OutputMode {
        case line
        case json
    }
    
}

// MARK:- ElasticLogHandler

/// - TODO: Add capability to send log to multiple handler/locations like stdout, file, tcp, udp etc.
public struct ElasticLogHandler: LogHandler {
    
    public var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }
    private var prettyMetadata: String?
    
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
    
    public let tcpClient: TCPClient
    
    public let label: String
    
    public let outMode: ElasticLogSystem.OutputMode
    
    private let encoder: JSONEncoder
    
    private let dateFormatter: DateFormatter?
    private var millisScince1970 = false
    private var secondsSince1970 = false
    
    public init(label: String, tcpClient: TCPClient, outputMode: ElasticLogSystem.OutputMode = .json, encoder: JSONEncoder? = nil) {
        self.label = label
        self.tcpClient = tcpClient
        self.outMode = outputMode
        if let encoder = encoder {
            self.encoder = encoder
        } else {
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
            self.encoder = jsonEncoder
        }
        let dateStrategy = self.encoder.dateEncodingStrategy
        switch dateStrategy {
        case .millisecondsSince1970:
            self.millisScince1970 = true
            self.dateFormatter = nil
        case .secondsSince1970:
            self.secondsSince1970 = true
            self.dateFormatter = nil
        default:
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            self.dateFormatter =  dateFormatter
        }
    }
    
    
    public func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        
        var data: Data? = nil
        switch self.outMode {
        case .json:
            data = self.getJsonData(level: level, message: message, metadata: metadata, file: file, function: function, line: line)
        case .line:
            data = "\(self.getTimestamp()) \(level) \(self.label): \(self.prettyMetadata ?? "") \(self.prettify(metadata ?? [:]) ?? "") \(message)".data(using: .utf8)
        }
        precondition(data != nil, "Unable to convert log to data")
        tcpClient.execute(data!).whenComplete { result in
            switch result {
            case .failure(let error):
                print("Error while writing logs to socket; LogData: \(String(data: data!, encoding: .utf8) ?? "Unable to decode LogData to string"); Error: \(error)")
            case .success(let res):
                if let str = String(data: res, encoding: .utf8) {
                    print("Success: \(str)")
                }
                print("Response: \(res)")
            }
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
    
    private func prettify(_ metadata: Logger.Metadata) -> String? {
        return !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : nil
    }
    
    
    private func getJsonData(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) -> Data? {
        let logEntry: LogEntry = .init(timestamp: Date(), level: level, metaData: metadata ?? [:], message: message, line: line, file: file, function: function, label: self.label)
        do {
            return try self.encoder.encode(logEntry)
        } catch {
            print("Error while encoding log entry to json; LogEntry: \(logEntry); Error: \(error)")
            return nil
        }
    }
    
    private func getTimestamp() -> String {
        let date = Date()
        if self.millisScince1970 {
            return "\(date.timeIntervalSince1970)"
        } else if self.secondsSince1970 {
            return "\(date.timeIntervalSince1970 / 1000)"
        } else if let formatter = self.dateFormatter {
            return formatter.string(from: date)
        } else {
            return "\(date)"
        }
    }
    
}

// MARK:- LogEntry

public struct LogEntry: Codable, Equatable {
    
    public let timestamp: Date
    public let level: Logger.Level
    public let metaData: Logger.Metadata
    public let message: Logger.Message
    public let line: UInt
    public let file: String
    public let `function`: String
    public let label: String
    
    enum CodingKeys: String, CodingKey {
        case timestamp = "@timestamp"
        case level
        case metaData
        case message
        case line
        case file
        case `function`
        case label
    }
    
}

// MARK:- Utility Extensions

extension Logger.Message: Codable {
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string =  try container.decode(String.self)
        self = Logger.Message.init(stringLiteral: string)
    }
}

extension Logger.MetadataValue: Codable {
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .array(let value):
            var container = encoder.unkeyedContainer()
            try container.encode(value)
        case .dictionary(let dic):
            var container = encoder.singleValueContainer()
            try container.encode(dic)
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .stringConvertible(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value.description)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let arr = try? container.decode([Logger.MetadataValue].self) {
            self =  .array(arr)
        } else {
            let dic = try container.decode([String: Logger.MetadataValue].self)
            let val: Logger.Metadata = dic
            self = .dictionary(val)
        }
    }
}
