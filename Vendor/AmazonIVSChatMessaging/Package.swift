// swift-tools-version: 5.10

// Vendored the same way as Vendor/AmazonIVSBroadcast — AWS doesn't host a git
// repo for the IVS Chat Messaging SDK, only a versioned XCFramework zip, so
// there's no remote SPM URL to point at. A local package wrapping a
// binaryTarget is the supported route.
//
// Version 1.0.1 is the newest AWS actually serves: 1.0.0 and 1.0.1 return 200,
// while 1.0.2 and above return 403 (checked 2026-10-08). Don't bump this
// speculatively — a wrong version is a 403 at dependency-resolution time, which
// fails the build before anything compiles.
//
// The checksum was computed on Windows by downloading the zip and running
// `sha256sum`, which produces the same value as `swift package
// compute-checksum` (both are a plain SHA-256 of the archive). That matters
// here because this project has no Mac — the archive was verified to contain
// real ios-arm64 and ios-arm64_x86_64-simulator slices before being wired in,
// rather than trusting the URL.
import PackageDescription

let package = Package(
    name: "AmazonIVSChatMessaging",
    platforms: [
        .iOS("14.0"),
    ],
    products: [
        .library(
            name: "AmazonIVSChatMessaging",
            targets: ["AmazonIVSChatMessaging"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "AmazonIVSChatMessaging",
            url: "https://ivschat.live-video.net/1.0.1/AmazonIVSChatMessaging.xcframework.zip",
            checksum: "9c0a3512ffc164a5f88c2a55d5fc834674f2e1f3649c61caad792c95e35a66ff"
        )
    ]
)
