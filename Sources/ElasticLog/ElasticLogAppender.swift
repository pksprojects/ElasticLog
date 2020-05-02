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
            if data.count > 0 {
                debugPrint("Response from logstash: \(String(data: data, encoding: .utf8) ?? "")")
            }
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

    public init(_ host: String, port: Int, bindHost: String = "0.0.0.0", bindPort: Int = 0, eventLoopProvider: EventLoopProvider = .createNew(threads: 1), sslContext: NIOSSLContext? = nil) throws {
        udpClient = try UDPClient(host, port: port, bindHost: bindHost, bindPort: bindPort, eventLoopProvider: eventLoopProvider, sslContext: sslContext)
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
        try self.init(settings.host, port: settings.port, bindHost: settings.bindHost, bindPort: settings.bindPort, eventLoopProvider: settings.eventLoopProvider, sslContext: sslContext)
    }

    public func execute(_ data: Data) -> EventLoopFuture<Void> {
        return udpClient.execute(data).map { data -> Void in
            if data.count > 0 {
                debugPrint("Response from logstash: \(String(data: data, encoding: .utf8) ?? "")")
            }
            return ()
        }
    }
}

extension LogstashUDPAppender {
    public struct Settings: LogAppenderSettings {
        
        public let appender: ElasticLogAppender.Type = LogstashUDPAppender.self

        public let host: String
        public let port: Int
        public let bindHost: String
        public let bindPort: Int
        public var useSSL: Bool = false
        public var tlsConfig: TLSConfiguration?
        public var eventLoopProvider: EventLoopProvider
        
        public init(host: String, port: Int, useSSL: Bool = false, tlsConfig: TLSConfiguration? = nil, bindHost: String = "0.0.0.0", bindPort: Int = 0,  eventLoopProvider: EventLoopProvider = .createNew(threads: 1)) {
            self.host = host
            self.port = port
            self.bindHost = bindHost
            self.bindPort = bindPort
            self.useSSL = useSSL
            self.tlsConfig = tlsConfig
            self.eventLoopProvider = eventLoopProvider
        }
    }
}
