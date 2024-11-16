//
//  ConsleIO.swift
//  appdump
//
//  Created by paradiseduo on 2021/7/29.
//

import Foundation

enum OutputType {
  case error
  case standard
}

class ConsoleIO {

  func normalizedPath(_ src: String, _ msg: String) -> String {
    // replace src in msg with ~
    return msg.replacingOccurrences(of: src, with: "@")
  }

  func writeMessage(_ message: String, to: OutputType = .standard) {
    let fileManager = FileManager.default

    var sourceUrl = CommandLine.arguments[1]
    if sourceUrl.hasSuffix("/") {
      sourceUrl.removeLast()
    }

    var targetUrl = CommandLine.arguments[2]
    if targetUrl.hasSuffix("/") {
      targetUrl.removeLast()
    }

    switch to {
    case .standard:
      print("[appdecrypt] \(self.normalizedPath(sourceUrl, message))")
    case .error:
      let nextMessage = self.normalizedPath(sourceUrl, message)

      if fileManager.fileExists(atPath: targetUrl + "/.fail") {
        let fileObj = FileHandle(forWritingAtPath: targetUrl + "/.fail")
        fileObj?.seekToEndOfFile()
        fileObj?.write("\n\(nextMessage)".data(using: .utf8)!)
        fileObj?.closeFile()
      } else {
        let failContent = "Target: \(targetUrl)\n\(nextMessage)"
        fileManager.createFile(
          atPath: targetUrl + "/.fail", contents: failContent.data(using: .utf8), attributes: nil)
      }

      fputs("[appdecrypt] Error: \(self.normalizedPath(sourceUrl, message))\n", stderr)
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: NSNotification.Name("stop"), object: nil)
      }
    }
  }

  func printUsage() {
    writeMessage(
      """
      Version \(version)

      appdecrypt is a tool to make decrypt application encrypted binaries on macOS when SIP-enabled.

      Examples:
        mac:
          appdecrypt /Application/Test.app /Users/admin/Desktop/Test.app
        iPhone:
          appdecrypt /var/containers/Bundle/Application/XXXXXX /tmp

      USAGE: appdecrypt encryptMachO_Path decryptMachO_Path [OPTIONS]

      ARGUMENTS:
        <encryptApp_Path>     The encrypt app file path.
        <decrypt_Path>        The path output file.

      OPTIONS:
        -h, --help              Show help information.
        -b, --binary            No copy app data, only decrypt binary.
        --ignore-ios-check      Decrypt the app even if M1 can't run it.
      """)
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: NSNotification.Name("stop"), object: nil)
    }
  }
}
