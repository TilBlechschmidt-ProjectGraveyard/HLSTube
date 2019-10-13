//
//  SimpleRegexMatcher.swift
//  Test
//
//  Created by Til Blechschmidt on 10.10.18.
//  Copyright © 2019 Til Blechschmidt. All rights reserved.
//

import Foundation

public struct SimpleRegexMatch {
    public let groups: [Substring?]
    public let ranges: [Range<String.Index>?]
}

public struct SimpleRegexMatcher {

    public static func matches(forPattern pattern: String, in string: String) -> [SimpleRegexMatch]? {
        let range = NSRange(location: 0, length: string.count)

        guard let regex = try? NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options()) else {
            return nil
        }

        return regex.matches(in: string, options: NSRegularExpression.MatchingOptions(), range: range).map { match in

            let ranges = (0..<match.numberOfRanges).map { rangeNumber in
                Range(match.range(at: rangeNumber), in: string)
            }
            
            let groups = ranges.compactMap { $0.flatMap { string[$0] } }

            return SimpleRegexMatch(groups: groups, ranges: ranges)
        }
    }

    public static func firstMatch(forPattern pattern: String, in string: String) -> SimpleRegexMatch? {
        let range = NSRange(location: 0, length: string.count)

        guard let regex = try? NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options()) else {
            return nil
        }

        guard let match = regex.firstMatch(in: string, options: NSRegularExpression.MatchingOptions(), range: range) else {
            return nil
        }
        
        let ranges = (0..<match.numberOfRanges).map { rangeNumber in
            Range(match.range(at: rangeNumber), in: string)
        }
        
        let groups = ranges.compactMap { $0.flatMap { string[$0] } }

        return SimpleRegexMatch(groups: groups, ranges: ranges)
    }
}
