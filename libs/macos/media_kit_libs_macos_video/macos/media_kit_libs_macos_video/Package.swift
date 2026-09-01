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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.2/libmpv-xcframeworks_0.6.8-mediaio.2_macos-universal-video-default"
let libmpvChecksums = [
    "Ass": "d4a621799b96e5ef4d2d4b5630d621c70651fa4268cd8d2f0a4d98e81c99b05d",
    "Avcodec": "d2347af2728cb6574f62ca4d50b118c2fe36f1290712605c5a5d2da7c4c76fc3",
    "Avfilter": "208badb02efb32f8612b4b2148a43c5a07f9292e57255cff90f9fd0d05914a70",
    "Avformat": "5a34a50cfc7ac73c5fe1209ddea3d69c2d77731fbc85ab9e71d35cd1f3624d6b",
    "Avutil": "7a21d58215263fdb65d17f5d1d30471975fbfa318a0082475227d363cadbc7c6",
    "Dav1d": "836983c2519f8da9ce12d2d9cfc63e9523c4e0cd0fae01429fcd13a9efe1d64a",
    "Freetype": "fada6902b308a552d8dcdd4b47ddc2488c7374251ce86f6d279d894ce67972a6",
    "Fribidi": "6f1679790ac010ee5e910779844f6952e86a8e160597eb6334e2fcbb42af756a",
    "Harfbuzz": "f3d35f3fdc0658f1b124b68608e26391aaf055b4e560f017909bd57597a6a78c",
    "Mbedcrypto": "d21f99a1b29b8fb930dec129bd63d60e3afd35c6829ac1a7e3e32a73f5b496fb",
    "Mbedtls": "6fbb964c3394b89488c94a32b1ca5b97fa0fad7ed41dfbd176beb7f25595f318",
    "Mbedx509": "da8677d349bfade2f268bccd35bf1a4b87ed6e7d4732aca324ece7b18cd3e586",
    "Mpv": "6e4862f06657768794c9c5103af2a3693f6940a8fe93d7a618719e979721450b",
    "Png16": "e7def65dc7794a19bc22395abc996d451b9b2e91fa4026fcbe8eba398c7843c9",
    "Swresample": "8a34d70689ba9f15be80b042a3530e080ceeaf1c41803de6d3066c9e5e60296b",
    "Swscale": "3a833776ec6025cf933596c089c17556d84cbc0b3129bda96cde86aade99732e",
    "Uchardet": "addbd2da332428fb91716d5315d4b7d6fa81424578f31b7c9adf5d003cd0faff",
    "Xml2": "2690823976f2cbdaeb7d02469fc99fd16ed2c8c51aea3776cf2f24193f6cac7e"
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
