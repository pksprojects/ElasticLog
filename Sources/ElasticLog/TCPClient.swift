//
//  TCPClient.swift
//  
//
//  Created by Prafull Kumar Soni on 12/21/19.
//

import Foundation
import NIO
import NIOSSL
import Logging

// MARK:- TCPClient

/// NIO based Basic TCP Client.
public class TCPClient {
    
    let group: EventLoopGroup
    let host: String
    let port: Int
    let sslContext: NIOSSLContext?
    private let isSharedPool: Bool
    
    let errorCallback: (Error?) -> Void = { error in  }
    
    public init(_ host: String, port: Int, eventLoopProvider: EventLoopProvider = .createNew(threads: 1), sslContext: NIOSSLContext? = nil) {
        self.host = host
        self.port = port
        switch eventLoopProvider {
        case .createNew(let threads):
            self.group = MultiThreadedEventLoopGroup(numberOfThreads: threads)
            self.isSharedPool = false
        case .shared(let group):
            self.group = group
            self.isSharedPool = true
        }
        
        self.sslContext = sslContext
    }
    
    public func execute(_ data: Data) -> EventLoopFuture<Data> {
        let promise = self.group.next().makePromise(of: Data.self)
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
                            return channel.pipeline.addHandler(handler)
                        }
                } else {
                    return channel.pipeline.addHandler(handler)
                }
        }
        
        return bootstrap.connect(host: self.host, port: self.port)
            .flatMap{ channel in
                return promise.futureResult
            }
//            .map { buffer in
//                var buf = buffer
//                if let bytes = buf.readBytes(length: buf.readableBytes) {
//                    return Data(bytes)
//                } else {
//                    return Data()
//                }
//        }
    }
    
    deinit {
        if !self.isSharedPool {
            group.shutdownGracefully(self.errorCallback)
        }
    }
    
}

// MARK:- Event Loop Provider

/// Enum to representing how EventLoopGroup should be managed.
public enum EventLoopProvider {
    
    case createNew(threads: Int)
    case shared(EventLoopGroup)
}

// MARK:- TCP Channel Handler

private final class TCPChannelHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    private let logger = Logger(label: "org.pksprojects.ElasticLog.TCPClient.TCPCHannelHandler")
    
    let data: Data
    let responsePromise: EventLoopPromise<Data>
    
    init(for data: Data, promise: EventLoopPromise<Data>) {
        self.data = data
        self.responsePromise = promise
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var response = self.unwrapInboundIn(data)
        
        if let bytes = response.readBytes(length: response.readableBytes) {
            self.responsePromise.succeed(Data(bytes))
        } else {
            self.responsePromise.succeed(Data())
        }
        context.close(promise: nil)
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        // As we are not really interested getting notified on success or failure we just pass nil as promise to
        // reduce allocations.
        self.responsePromise.fail(error)
        context.close(promise: nil)
    }
}

// MARK:- ChannelPipeline Extension

extension ChannelPipeline {
    /// Wrapper for `addHandler` that taking a throwing closure to build ChannelHandler
    func addHandlerThrowing(_ handlerFactory: () throws -> ChannelHandler) -> EventLoopFuture<Void> {
        do {
            let channel = try handlerFactory()
            return self.addHandler(channel)
        } catch {
            return self.eventLoop.makeFailedFuture(error)
        }
    }
    
}
