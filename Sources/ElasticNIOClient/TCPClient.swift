//
//  TCPClient.swift
//
//
//  Created by Prafull Kumar Soni on 12/21/19.
//

import Foundation
import Logging
import NIO
import NIOSSL

// MARK: - TCPClient

/// NIO based Basic TCP Client.
public class TCPClient {
    let group: EventLoopGroup
    let host: String
    let port: Int
    let sslContext: NIOSSLContext?
    private let isSharedPool: Bool

    let errorCallback: (Error?) -> Void = { _ in }

    public init(_ host: String, port: Int, eventLoopProvider: EventLoopProvider = .createNew(threads: 1), sslContext: NIOSSLContext? = nil) {
        self.host = host
        self.port = port
        switch eventLoopProvider {
        case let .createNew(threads):
            group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
            isSharedPool = false
        case let .shared(group):
            self.group = group
            isSharedPool = true
        }

        self.sslContext = sslContext
    }

    public func execute(_ data: Data) -> EventLoopFuture<Data> {
        let promise = group.next().makePromise(of: Data.self)
        let handler = TCPChannelHandler(for: data, promise: promise)
        let bootstrap = ClientBootstrap(group: group)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel in
                if let sslContext = self.sslContext {
                    return channel.pipeline.addHandlerThrowing {
                        let openSslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                        return openSslHandler
                    }.flatMap {
                        channel.pipeline.addHandler(handler)
                    }
                } else {
                    return channel.pipeline.addHandler(handler)
                }
            }

        bootstrap.connect(host: host, port: port).whenComplete { result in
            switch result {
            case let .failure(error):
                promise.fail(error)
            case .success:
                promise.succeed(Data())
            }
        }
        return promise.futureResult
    }

    deinit {
        if !self.isSharedPool {
            group.shutdownGracefully(self.errorCallback)
        }
    }
}

// MARK: - Event Loop Provider

/// Enum to representing how EventLoopGroup should be managed.
public enum EventLoopProvider {
    case createNew(threads: Int)
    case shared(EventLoopGroup)
}

// MARK: - TCP Channel Handler

private final class TCPChannelHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer

    private let logger = Logger(label: "org.pksprojects.ElasticLog.TCPClient.TCPCHannelHandler")

    let data: Data
    let responsePromise: EventLoopPromise<Data>

    init(for data: Data, promise: EventLoopPromise<Data>) {
        self.data = data
        responsePromise = promise
    }

    public func channelActive(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var response = unwrapInboundIn(data)

        if let bytes = response.readBytes(length: response.readableBytes) {
            responsePromise.succeed(Data(bytes))
        } else {
            responsePromise.succeed(Data())
        }
        context.close(promise: nil)
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        responsePromise.fail(error)
        context.close(promise: nil)
    }
}

// MARK: - ChannelPipeline Extension

extension ChannelPipeline {
    /// Wrapper for `addHandler` that taking a throwing closure to build ChannelHandler
    func addHandlerThrowing(_ handlerFactory: () throws -> ChannelHandler) -> EventLoopFuture<Void> {
        do {
            let channel = try handlerFactory()
            return addHandler(channel)
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }
}
