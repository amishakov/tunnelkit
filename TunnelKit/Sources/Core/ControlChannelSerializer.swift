//
//  ControlChannelSerializer.swift
//  TunnelKit
//
//  Created by Davide De Rosa on 9/10/18.
//  Copyright (c) 2018 Davide De Rosa. All rights reserved.
//
//  https://github.com/keeshux
//
//  This file is part of TunnelKit.
//
//  TunnelKit is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  TunnelKit is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with TunnelKit.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import __TunnelKitNative
import SwiftyBeaver

private let log = SwiftyBeaver.self

protocol ControlChannelSerializer {
    func reset()
    
    func serialize(packet: ControlPacket) throws -> Data

    func deserialize(code: PacketCode, key: UInt8, data: Data, start: Int, end: Int?) throws -> ControlPacket
}

extension ControlChannel {
    class PlainSerializer: ControlChannelSerializer {
        func reset() {
        }
        
        func serialize(packet: ControlPacket) throws -> Data {
            return packet.serialized()
        }
        
        func deserialize(code: PacketCode, key: UInt8, data packet: Data, start: Int, end: Int?) throws -> ControlPacket {
            var offset = start
            let end = end ?? packet.count

            guard end >= offset + PacketSessionIdLength else {
                throw ControlChannelError("Missing sessionId")
            }
            let sessionId = packet.subdata(offset: offset, count: PacketSessionIdLength)
            offset += PacketSessionIdLength

            guard end >= offset + 1 else {
                throw ControlChannelError("Missing ackSize")
            }
            let ackSize = packet[offset]
            offset += 1

            var ackIds: [UInt32]?
            var ackRemoteSessionId: Data?
            if ackSize > 0 {
                guard end >= (offset + Int(ackSize) * PacketIdLength) else {
                    throw ControlChannelError("Missing acks")
                }
                var ids: [UInt32] = []
                for _ in 0..<ackSize {
                    let id = packet.networkUInt32Value(from: offset)
                    ids.append(id)
                    offset += PacketIdLength
                }

                guard end >= offset + PacketSessionIdLength else {
                    throw ControlChannelError("Missing remoteSessionId")
                }
                let remoteSessionId = packet.subdata(offset: offset, count: PacketSessionIdLength)
                offset += PacketSessionIdLength

                log.debug("Server acked packetIds \(ids) with remoteSessionId \(remoteSessionId.toHex())")
                
                ackIds = ids
                ackRemoteSessionId = remoteSessionId
            }

            if code == .ackV1 {
                guard let ackIds = ackIds else {
                    throw ControlChannelError("Ack packet without ids")
                }
                guard let ackRemoteSessionId = ackRemoteSessionId else {
                    throw ControlChannelError("Ack packet without remoteSessionId")
                }
                return ControlPacket(key: key, sessionId: sessionId, ackIds: ackIds as [NSNumber], ackRemoteSessionId: ackRemoteSessionId)
            }

            guard end >= offset + PacketIdLength else {
                throw ControlChannelError("Missing packetId")
            }
            let packetId = packet.networkUInt32Value(from: offset)
            log.debug("Control packet has packetId \(packetId)")
            offset += PacketIdLength

            var payload: Data?
            if offset < end {
                payload = packet.subdata(in: offset..<end)

                if let payload = payload {
                    if CoreConfiguration.logsSensitiveData {
                        log.debug("Control packet payload (\(payload.count) bytes): \(payload.toHex())")
                    } else {
                        log.debug("Control packet payload (\(payload.count) bytes)")
                    }
                }
            }

            let controlPacket = ControlPacket(code: code, key: key, sessionId: sessionId, packetId: packetId, payload: payload)
            if let ackIds = ackIds {
                controlPacket.ackIds = ackIds as [NSNumber]
                controlPacket.ackRemoteSessionId = ackRemoteSessionId
            }
            return controlPacket
        }
    }
}
