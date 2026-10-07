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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.5/libmpv-xcframeworks_0.6.8-mediaio.5_macos-universal-video-default"
let libmpvChecksums = [
    "Ass": "803eddeca013e8c12d3fe1a3cc199f0d6e5882b0d0e9226a023c09e0e9683c1f",
    "Avcodec": "96081a2f0f0167a4ce921a9cb419cb38bc98c9f310521e96e5bf9a15e7b3ff96",
    "Avfilter": "13daf4047682b99bf73416989ae0a7283968196a4e7466c7ee6b8f019ae74945",
    "Avformat": "817de2cc0ece0aaeff730671f0e2d97787e54a924cead589ad337ad8ec8e547a",
    "Avutil": "534574877a0dd755a56d6e7960c2b091bc1f6008ca769791a28a09f540d86d70",
    "Dav1d": "3f2341d5e42203773971b1594880bf4f453ad16c0b9aea8c038b80cd2e9a5ec6",
    "Freetype": "25b392fb375a6b87bcc18b565e6a9b4ba9509361b5409725668fc5520482fab7",
    "Fribidi": "defda5a4fbb8f8811b6c87729deeeaff68053c9065084fd3c3fbc3c729e841c5",
    "Harfbuzz": "641dcf3c8317c4884e182f9a3e6c00c8822ce9f9bd5394066090b6e1f7d820d4",
    "Mbedcrypto": "a6945d440b8bc6dadb995e8e4a52baf1e1b127cdae618c6a79dc86292ef8ec48",
    "Mbedtls": "352890cef32df2475195552d1de95d1bfc0a464b92672faa179026681b8f7de7",
    "Mbedx509": "fd06bab88e0cd5977dc32f5903d2c62604bf552a39d011a2e79800e67f7b0ccf",
    "Mpv": "aebbe24f65326f409097ea4bd8b942d4931371b7f484c7f8ff94b06e4a32a5e1",
    "Png16": "2ca891a26a868270479ea8bb06eee225409743891494a52c0cab81894f755441",
    "Swresample": "22b8f314ca150a44068d3c7e9e79306a989a8f603a0f210c225fb0bbba17ad68",
    "Swscale": "f0ab5db217361dd8134529e69fbc82fdb1c04c5e46e92519795b829dc197cc25",
    "Uchardet": "ecdade903d77a39d7e149701b0a4ae0c6fdf18dddb971b9a600d6a4e2646d24e",
    "Xml2": "5c15d2177e8515827089e9a8ba2a243e8af6632d687c9fff0189bcb652abb0d3"
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
