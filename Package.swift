// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "d3crypt",
  products: [
    .executable(
      name: "d3crypt",
      targets: ["appdecrypt"]
    )
  ],
  targets: [
    .target(name: "appdecrypt")
  ]
)
