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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.3/libmpv-xcframeworks_0.6.8-mediaio.3_macos-universal-video-default"
let libmpvChecksums = [
    "Ass": "0a5b16f62881ce62edb6bb80ef095d95a9cd33b70c03b21330931111fe906625",
    "Avcodec": "24faa3b8061c6363d0212a5637fa0648d98e4d9bb118f3cf3b040dd368e4f2f5",
    "Avfilter": "d4c0f94d4abd999f02788600dd45119c3c8c6fda051a873a2113d3e9c6613a37",
    "Avformat": "5dba5f1217b4ef3f83e80270b45af43ede7028a0444ef4c0c0721713f4709d3a",
    "Avutil": "2afc23cf21f2f355f36dde74501e625dbcfeb713cecf12416470d8af4215acff",
    "Dav1d": "4ea0020fe92a685c0dc9443ff0c8f064e355f0ab0ddb24acdf9b0f8a0b8950e3",
    "Freetype": "8b24033678c934ff6527cb7d5b4da9095379fb4e586cc5c414e8d00bef512732",
    "Fribidi": "7e4efc0c3a22aae5f469351c945e0894058f5030e5370cbe23ae4c50d0b6b146",
    "Harfbuzz": "15a717e9631ee91bd410c259d3771d6e2cc987aab5638afb5e74d42f843d4de0",
    "Mbedcrypto": "3a912f05eba0f1190fa8bb7ce67a254414f19a3255b4fba20aff73257f1e205e",
    "Mbedtls": "14fe541c4682e28d14e509a282f91c2267058dfd10200e17789ddec34158f683",
    "Mbedx509": "7b023eb006f22f7075bd68dafaf78286822f81d17510ec9240022f6b0748791a",
    "Mpv": "1f8e1c91acc6e5024542a2c15801358fac5cf77ce8970aac53e0be4d2c3beeb7",
    "Png16": "4834d602ed81c4929a8b17d744730bd4de6be04d68d6638aafdfbeea5a813951",
    "Swresample": "13aa42ac62799975deed0bca092afbb7072d8f69cf9edf189a1a006b2782c37a",
    "Swscale": "a04a243d539b9a57a1678bb621d431d22d552c4b3e1d0df7e0bb578907c28386",
    "Uchardet": "0e5f8e26724f964f73579a345c283fcd3cdb87f4fadbcde81e3158dc6dd3da42",
    "Xml2": "2357b2ead3320b8a05df59e781a5e7ced7649170ff8e8a19f0d6cafa69b6efe2"
]
let libmpvProductTargets: [String] = ["media_kit_libs_macos_video"] + libmpvTargets

let package = Package(
    name: "media_kit_libs_macos_video",
    platforms: [
        .macOS("10.9")
    ],
    products: [
        .library(name: "media-kit-libs-macos-video", targets: libmpvProductTargets),
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
            name: "media_kit_libs_macos_video",
            dependencies: libmpvTargets.map { framework in .target(name: framework) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
