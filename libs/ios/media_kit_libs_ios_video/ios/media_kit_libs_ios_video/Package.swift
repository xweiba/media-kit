// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let libmpvTargets = [
    "Ass",
    "Avcodec",
    "Avfilter",
    "Avformat",
    "Avutil",
    "Dav1d",
    "Freetype",
    "Fribidi",
    "Harfbuzz",
    "Mbedcrypto",
    "Mbedtls",
    "Mbedx509",
    "Mpv",
    "Png16",
    "Swresample",
    "Swscale",
    "Uchardet",
    "Xml2"
]

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.6/libmpv-xcframeworks_0.6.8-mediaio.6_ios-universal-video-default"
let libmpvChecksums = [
    "Ass": "6c61220ba84c5199b158c26152e883c4e6287c4d6abeeb369968b854663cd443",
    "Avcodec": "9c9e40d4b4f7848cef11aa9cad4c6f41f1d9bf27db0912a8a6379a62aa5385e4",
    "Avfilter": "dc20bb2ba89fcf897fb4c95ee3eef364f3ef9667b9b6c088ea98c0d47600a8f9",
    "Avformat": "591a2ae853a0dbe1cc4773308c86757459efa192b3068853cb8243f4377e20bb",
    "Avutil": "8af4dcbc4b658792c777653d4ce1ea40bd28b8a5e637295a85cd049a9b212506",
    "Dav1d": "7db144769ad2483d510a166b3bc0fb2630e2833cd03245becbc3441aea93f409",
    "Freetype": "51b06559f19450d38df4b2866221e66c20f3f20c4964b9898749ff0e4483a431",
    "Fribidi": "a7a6aef2930fa4464d8289408a7d09795cdc8f51deb913865f81d72ef75335e6",
    "Harfbuzz": "8f4b325e46b293af5f6b4128aa29420b075033241797f5a7d792759606e74fd7",
    "Mbedcrypto": "af78094d67f87ac5899561f6dc1ff2c0abb23be941740e492959133df01dcff0",
    "Mbedtls": "6d46b7a9e4aa225c531257c9f10464e87622925b936f8bc36c45011a5fa15d3a",
    "Mbedx509": "89c0127a34340ccb0e234140110a56d111440bcd54cdcb7de7a514a662c6cb85",
    "Mpv": "5537289138359ed77c0ca9c11e12987b0c704aac01634212033fcae2df124599",
    "Png16": "b538ace4902c0a78eb7a2210230f090dbd77f660dc9a45a3df5c70854f54c231",
    "Swresample": "bcb758246b394c82c11d95a0c19515be6baa703f859df737bcf833119a6f6cf5",
    "Swscale": "59bc48bc5f533486aa71fe4754745600461fd42fcaf481551710528b73d77f05",
    "Uchardet": "359565c7dfe3af7b650365f473c64c5db98ba929a05c8eccac0fa7695d46cf13",
    "Xml2": "6afaa1f2e510c180e8d0d4bad9ab7b63ced96f17de73b8c3f662ffc1f11ac6ce"
]
let libmpvProductTargets: [String] = ["media_kit_libs_ios_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_ios_video",
    platforms: [
        .iOS("9.0")
    ],
    products: [
        .library(name: "media-kit-libs-ios-video", targets: libmpvProductTargets),
        .library(name: "Mpv", targets: ["Mpv"])
    ],
    dependencies: [],
    targets: libmpvTargets.map { framework in
        .binaryTarget(
            name: framework,
            url: "\(libmpvArtifactBase)_\(framework).zip",
            checksum: libmpvChecksums[framework]!
        )
    } + [
        .target(
            name: "media_kit_libs_ios_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
