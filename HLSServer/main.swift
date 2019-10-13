//
//  main.swift
//  HLSServer
//
//  Created by Til Blechschmidt on 12.10.19.
//

import Foundation
import HLSTube
import JavaScriptCore

print("Hello, World!")

// Regular video:
// http://localhost:1337/4Ip1H-a42so.m3u8

// Signed video:
// http://localhost:1337/rrLSgt5_uuw.m3u8

// Signed video that stops after quality change:
// http://localhost:1337/Cp5WWtMoeKg.m3u8

let server = try! HLSServer(port: 1337)
server.listen()

RunLoop.current.run()


