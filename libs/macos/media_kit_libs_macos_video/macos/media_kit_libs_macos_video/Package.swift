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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.1/libmpv-xcframeworks_0.6.8-mediaio.1_macos-universal-video-default"
let libmpvChecksums = [
    "Ass": "139d460bb32f82814da8485f52c3cb51cc0c4c35f0e45e436a07b192ee9ea399",
    "Avcodec": "b11aa18f3a4dd82c87cf2d652ccdc77850e15d872c841c1904b67cc7126b2254",
    "Avfilter": "6109f122d5df6199d108dce328d9056ab200ba8a05eb8cb8cb5218649580f60b",
    "Avformat": "465397a608be41c056732a7bf7c8e3c0691352ae235c8c5bd77d4783bd187761",
    "Avutil": "ec06013a98fb28bebf9c2c4c995fe502c46b3dbbc1862912b511dd82fa1bd573",
    "Dav1d": "47079a6550af6c69b6893defc01b1ae02c0d404d92369ec1c7fa9a6be05a4448",
    "Freetype": "a9f7a0870a5acced85937251bd44884a0f9c1c5071e12c1938a84468b53e9af9",
    "Fribidi": "2df3fa93d0a17f2bf9b2b564ebf9e8c727630dcff692d40e4e35dbdd90bfbc7a",
    "Harfbuzz": "896ae2a9dd830e2f2315504d57a02b5083e05a848b620539b0fccf7a321dbbcb",
    "Mbedcrypto": "37393763c85e6090e1ec785ccd506d96190b5b4b5fcebe841a946dcdfdbb243a",
    "Mbedtls": "9021a1e663873151bf2ec05b8084d7779b66d5b14779dca4fb2c6202e497add8",
    "Mbedx509": "63c790db89e56d2a598aac5f49f65b43990951dce7182b3c7cf8d3f384e6a9ca",
    "Mpv": "966eb57e0b9c6bfc367b92956159e45f0bf5987e8e58a3c3d6d7ceab299d4a03",
    "Png16": "5396936b56cc2c88786a3bc9990b3686d26196e030460bf023c3cb0eead4e01e",
    "Swresample": "71023c5701b58a568eeaabd0a481d848314c099d38c07c5bb256c4677cade02a",
    "Swscale": "a4d24bb121ef5db39d8f89da207274b93cda3d5b13e8a042e2d93f1e3eef5b43",
    "Uchardet": "00f853298758a365910737ea4a6e3a1ac28ba4706772c7c6b720e485de21e0c3",
    "Xml2": "f116fbe1621a29fd4bde8cbedb3539d59cb9dacdd61c7ff939c24f6bc2567c9d"
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
