//
//  DataReader.swift
//  HLSServer
//
//  Created by Til Blechschmidt on 20.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation

public class DataReader {
    private let data: Data
    internal private(set) var offset: Int

    public init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public func advance(byBytes bytes: Int) {
        offset += bytes
    }

    public func readByte() -> UInt8 {
        defer {
            offset += 1
        }
        return data[offset]
    }

    public func read(bytes: UInt8) -> UInt64 {
        return (0..<bytes).reduce(0) { acc, byteIndex in
            let byte = readByte()
            let shift = (bytes - 1 - byteIndex) * 8
            return acc | (UInt64(byte) << shift)
        }
    }
}
