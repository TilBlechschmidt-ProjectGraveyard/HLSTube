//
//  MP4Parser.swift
//  HLSServer
//
//  Created by Til Blechschmidt on 20.04.19.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation

enum SegmentError: Error {
    case noDataAvailable
}

struct Segment {
    let referencedSize: UInt64
    let subSegmentDuration: UInt64
}

struct SegmentInformation {
    public let version: UInt8
    public let flags: UInt64
    public let referenceID: UInt64
    public let timescale: UInt64
    public let earliestPresentationTime: UInt64
    public let firstOffset: UInt64
    public let indexRange: Range<Int>
    public let segments: [Segment]

    public init(fromData data: Data, inRange indexRange: Range<Int>) throws {
        self.indexRange = indexRange

        let subdata = data.subdata(in: indexRange)
        let sidx = DataReader(data: subdata)
        
        guard subdata.count == indexRange.count else {
            throw SegmentError.noDataAvailable
        }

        // No idea what data is in there but lets just skip it.
        sidx.advance(byBytes: 8)

        version = sidx.readByte()
        flags = sidx.read(bytes: 3)
        referenceID = sidx.read(bytes: 4)
        timescale = sidx.read(bytes: 4)
        earliestPresentationTime = sidx.read(bytes: version == 0 ? 4 : 8)
        firstOffset = sidx.read(bytes: 4)

        sidx.advance(byBytes: 2) // reserved

        segments = (0..<sidx.read(bytes: 2)).map { _ in
            let referencedSize = sidx.read(bytes: 4)
            let subSegmentDuration = sidx.read(bytes: 4)
            sidx.advance(byBytes: 4) // unused
            return Segment(referencedSize: referencedSize, subSegmentDuration: subSegmentDuration)
        }

        assert(sidx.offset == indexRange.count)
    }

    public func generateM3U8(withFilePath path: String) -> String {
        let targetDuration = segments.map { Float($0.subSegmentDuration) / Float(timescale) }.max()
        var offset: UInt64 = UInt64(indexRange.endIndex)

        var m3u8 = """
        #EXTM3U
        #EXT-X-TARGETDURATION:\(Int(round(targetDuration ?? 5)))
        #EXT-X-VERSION:7
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MAP:URI="\(path)",BYTERANGE="\(offset)@0"

        """

        segments.forEach { segment in
            let duration = Float(segment.subSegmentDuration) / Float(timescale)

            m3u8 += """
            #EXTINF:\(String(format: "%.5f", duration)),
            #EXT-X-BYTERANGE:\(segment.referencedSize)@\(offset)
            \(path)

            """

            offset += segment.referencedSize
        }

        m3u8 += "#EXT-X-ENDLIST"

        return m3u8
    }
}
