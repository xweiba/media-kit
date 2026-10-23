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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.7/libmpv-xcframeworks_0.6.8-mediaio.7_macos-universal-video-default"
let libmpvChecksums = [
    "Ass": "006e94f6d7ff02848d9488a284628f4d01410e832cdbe96c510e48082b917b48",
    "Avcodec": "d14e034aee9b8aad48793ab346c23047b0540488d115cc04cba0012e5dc418dc",
    "Avfilter": "31134cb1e7127bcb02642998660fa1e656a5c94f21ce8a6632fa3b1654d6ebcf",
    "Avformat": "0edf03a6f6cd58c6b476c498b3a086508254f12db4293ac566796ea11d7f0e45",
    "Avutil": "bdf0bc3df81ebc6888c3d712e4b7024667d2b36fbb163aa0695a780d011c6a84",
    "Dav1d": "68693814f1fa5b38cb4d40138beec3eed5a1418bd3a87900f1cce55fa80b1cf0",
    "Freetype": "07e37c80d64dcea4b3a46facc1215a48dabb520125f2ed625537dbd4b53f3e55",
    "Fribidi": "1ece940fadd78b34cc77d9af44abe887600a38eee1167a017766e52857170b27",
    "Harfbuzz": "4c6402e20b2df1b53d22abf60be23f2e0ca3f534cae0114fb6fdc196c18fb346",
    "Mbedcrypto": "8d20cc0ac0b8faa54a473a19d425abe9d731869936914bfb29e54b6fc794e474",
    "Mbedtls": "db71374d00f5f061d2e065bdfcf31cb3d28fea28c87c3f46af58b0db4571bea0",
    "Mbedx509": "64f11e682737601eec1e767ff4b879ce3af7da085538c6fbe9d9e69ae5dac519",
    "Mpv": "7d59f537b333c1ebb5667026cdcf86a381700779197f0ea98a52ddc2f9c90701",
    "Png16": "affa889f6684e46c2ed59e5d1529b5eec03f2d273bfed63951e1732d581f370d",
    "Swresample": "7b3e40a7c43c17b1e4a2452bdf769bcad6082fc4ed01a22a2ba533eecebbbd69",
    "Swscale": "f03f0d4013b77abe6f6b792c0db298265a273b95cb68ff777d2ea2cdaf7dceb2",
    "Uchardet": "3c983c1e77841d6d17905b3c15609e64e7bc58df0de8e7bf5d2b576e839a833b",
    "Xml2": "63f81a050da5e3e328f2802872024bb7a938c3203c59f3e224cfcd9da58d1895"
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
