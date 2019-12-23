//
//  UDPClient.swift
//  
//
//  Created by Prafull Kumar Soni on 12/22/19.
//

import Foundation
import NIO
import NIOSSL
import Logging

// MARK:- TCPClient

/// NIO based Basic TCP Client.
public class UDPClient {
    
    let group: EventLoopGroup
    let host: String
    let port: Int
    let listenPort: Int
    let sslContext: NIOSSLContext?
    private let isSharedPool: Bool
    let socketAddress: SocketAddress
    
    let errorCallback: (Error?) -> Void = { error in  }
    
    public init(_ host: String, port: Int, listenPort: Int, eventLoopProvider: EventLoopProvider = .createNew(threads: 1), sslContext: NIOSSLContext? = nil) throws {
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
        self.socketAddress = try SocketAddress.makeAddressResolvingHost(self.host, port: self.port)
        self.listenPort = listenPort
    }
    
    public func execute(_ msg: String) -> EventLoopFuture<Data> {
        let promise = self.group.next().makePromise(of: Data.self)
        let handler = UDPChannelHandler(for: msg.data(using: .utf8)!, remote: self.socketAddress, promise: promise)
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
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
        return bootstrap.bind(host: self.host, port: self.listenPort)
            .flatMap { channel in promise.futureResult }
    }
    
    deinit {
        if !self.isSharedPool {
            group.shutdownGracefully(self.errorCallback)
        }
    }
    
}

// MARK:- UDP Channel Handler

private final class UDPChannelHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    
    private let logger = Logger(label: "org.pksprojects.ElasticLog.UDPClient.UDPCHannelHandler")
    
    let data: Data
    let remoteAddress: SocketAddress
    let responsePromise: EventLoopPromise<Data>
    
    init(for data: Data, remote: SocketAddress, promise: EventLoopPromise<Data>) {
        self.data = data
        self.responsePromise = promise
        self.remoteAddress = remote
    }
    
    public func channelActive(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let addBuffer = AddressedEnvelope<ByteBuffer>.init(remoteAddress: remoteAddress, data: buffer)
        context.writeAndFlush(self.wrapOutboundOut(addBuffer), promise: nil)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var response = self.unwrapInboundIn(data)
        if let bytes = response.data.readBytes(length: response.data.readableBytes) {
            self.responsePromise.succeed(Data(bytes))
        } else {
            self.responsePromise.succeed(Data())
        }
        context.close(promise: nil)
    }
}
