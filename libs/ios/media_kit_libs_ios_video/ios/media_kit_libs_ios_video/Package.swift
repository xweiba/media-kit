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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.3/libmpv-xcframeworks_0.6.8-mediaio.3_ios-universal-video-default"
let libmpvChecksums = [
    "Ass": "f7dd08e611f940768b4192772d61e5a487ca6c6972ee9538584a2895d8eb3666",
    "Avcodec": "4a6ccc7d445fd798f29ef9cc0840058b7927f1e9a9150adbac259f0eb05dc96d",
    "Avfilter": "2f507b1ef493f5751857ab6a170eb7b3d67e71301a3fa017969acfbbc54d766d",
    "Avformat": "11bdffd25bdbb528c51351d7b65330e5d302be38b1d96f61cd101ff207fd7f08",
    "Avutil": "111bcb1e4da904f6e25b07f87966982a22986af01cebc58b6f09b6c361a9a111",
    "Dav1d": "5f3d05396744da29275b2913114ad4908c1b2b9ef0de95a0da59967abb677394",
    "Freetype": "d687f0a1b5eaa8ab04381636b981071f1ccc02c089450dc55e71f4dcec38f928",
    "Fribidi": "e0062e2dbbe059d29cc081c40118e41928ba89b58da70aa77b2cb55f5ada18d6",
    "Harfbuzz": "9c253f27f57ed6806d065094a27ae97e5e776cf14e15f417ff90f02eb7d419d2",
    "Mbedcrypto": "b9de33283a19656ade27d357e96ba5b34be480a4ee5c267f7af4d06c80561c8d",
    "Mbedtls": "efeb15bf7a25b8565965a4b0b9345ffaa2837c95ba0737f62c79d2b8735b1d36",
    "Mbedx509": "78841c2cfab31c882dae43a82ab7f8f79ea9ba59718d7c2e00cb2d3eff1a501d",
    "Mpv": "7658eb73480533294775243df5910115e2de33f0809ee8ebd89101722691ac57",
    "Png16": "4d732b8aeb26830d90a4b959762bdceb3630c34eac9eb7d465c4e90d0a527504",
    "Swresample": "cecd2ff3bc2e0f21e8240b4d2536f9a13a2c03ee6d6d777098acbd0998ae458b",
    "Swscale": "8db1f5cc411490269ae47e24dc9358de22d9a333d74cd53243800cc3933bb327",
    "Uchardet": "38dea544d9ae24db162a962ca9e3ea5de7754d3c55e6a66e662416048f3af3e7",
    "Xml2": "0827a112c5a600299a057856326d4822c38c5c0fdc50e97dfc0af5789ee7fe03"
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
