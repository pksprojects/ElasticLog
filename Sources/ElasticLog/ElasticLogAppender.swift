//
//  ElasticLogAppender.swift
//
//
//  Created by Prafull Kumar Soni on 3/21/20.
//

import ElasticNIOClient
import Foundation
import Logging
import NIO
import NIOSSL

public protocol ElasticLogAppender {
    init(_ settings: LogAppenderSettings) throws

    func execute(_ data: Data) -> EventLoopFuture<Void>
}

public protocol LogAppenderSettings {
    var appender: ElasticLogAppender.Type { get }
}

public class LogstashTCPAppender: ElasticLogAppender {
    public let tcpClient: TCPClient

    public init(_ host: String, port: Int, eventLoopProvider: EventLoopProvider = .createNew(threads: 1), sslContext: NIOSSLContext? = nil) {
        tcpClient = TCPClient(host, port: port, eventLoopProvider: eventLoopProvider, sslContext: sslContext)
    }

    public required convenience init(_ appenderSettings: LogAppenderSettings) throws {
        precondition((appenderSettings as? LogstashTCPAppender.Settings) != nil)
        let settings = appenderSettings as! LogstashTCPAppender.Settings
        var sslContext: NIOSSLContext?
        if settings.useSSL, settings.tlsConfig == nil {
            let tlsConfig = TLSConfiguration.clientDefault
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        } else if let tlsConfig = settings.tlsConfig {
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        }
        self.init(settings.host, port: settings.port, eventLoopProvider: settings.eventLoopProvider, sslContext: sslContext)
    }

    public func execute(_ data: Data) -> EventLoopFuture<Void> {
        return tcpClient.execute(data).map { data -> Void in
            print(data)
            return ()
        }
    }
}

extension LogstashTCPAppender {
    public struct Settings: LogAppenderSettings {
        public let appender: ElasticLogAppender.Type = LogstashTCPAppender.self

        public let host: String
        public let port: Int
        public var useSSL: Bool = false
        public var tlsConfig: TLSConfiguration?
        public var eventLoopProvider: EventLoopProvider = .createNew(threads: 1)
    }
}

public class LogstashUDPAppender: ElasticLogAppender {
    public let udpClient: UDPClient

    public init(_ host: String, port: Int, listenPort: Int, eventLoopProvider: EventLoopProvider = .createNew(threads: 1), sslContext: NIOSSLContext? = nil) throws {
        udpClient = try UDPClient(host, port: port, listenPort: listenPort, eventLoopProvider: eventLoopProvider, sslContext: sslContext)
    }

    public required convenience init(_ appenderSettings: LogAppenderSettings) throws {
        precondition((appenderSettings as? LogstashUDPAppender.Settings) != nil)
        let settings = appenderSettings as! LogstashUDPAppender.Settings
        var sslContext: NIOSSLContext?
        if settings.useSSL, settings.tlsConfig == nil {
            let tlsConfig = TLSConfiguration.clientDefault
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        } else if let tlsConfig = settings.tlsConfig {
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        }
        try self.init(settings.host, port: settings.port, listenPort: settings.listenPort, eventLoopProvider: settings.eventLoopProvider, sslContext: sslContext)
    }

    public func execute(_ data: Data) -> EventLoopFuture<Void> {
        return udpClient.execute(data).map { data -> Void in
            print(data)
            return ()
        }
    }
}

extension LogstashUDPAppender {
    public struct Settings: LogAppenderSettings {
        public let appender: ElasticLogAppender.Type = LogstashUDPAppender.self

        public let host: String
        public let port: Int
        public let listenPort: Int
        public var useSSL: Bool = false
        public var tlsConfig: TLSConfiguration?
        public var eventLoopProvider: EventLoopProvider = .createNew(threads: 1)
    }
}