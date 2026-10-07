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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.5/libmpv-xcframeworks_0.6.8-mediaio.5_ios-universal-video-default"
let libmpvChecksums = [
    "Ass": "05bbf19308fa7b8f2734c663b68d7bfcbcd67d49f43fbc5d3d54f9ab6d737d9a",
    "Avcodec": "afc1aad0556b894d49398b64614ca1a51d89cb853806ed8227f8e1077faadb0f",
    "Avfilter": "885839e998fab83d45c267315350512c847ae2fb3091c8af5b0541dbce16ee40",
    "Avformat": "70ba73b09ae1468c34fac386444e11391a82be90fd8bcd69fb26dfdd73f12118",
    "Avutil": "01c63108552e6e64c6965aa0f927351e7697e10b971534236f9e8e0a61a9ea8f",
    "Dav1d": "1aee1bf00b5e15fd13c78ae0fbdd6aa97430884b269b6c31019b5d5f5a0d9eb8",
    "Freetype": "9fb375c52b84bbf2afe7c3a4cbe5df7b95a586c5d5af29b63a6e5ee958be87fd",
    "Fribidi": "01c3e390ffa697c89bb79e17ca4ee955c6cbb9c0c178732cfaa7a38c0ba025dc",
    "Harfbuzz": "25eff70133721f7f25a85a66c16a1a28fbda5426941877df02f726d9b3c67d25",
    "Mbedcrypto": "1f20c9ee691e7b117ad301b7128f8926650d15477d2cb509cd6004e54dc8de9d",
    "Mbedtls": "284046827e6f1b07f2fbcd803e7e39687442ce0e2ea81c5c28d9b84f53a27365",
    "Mbedx509": "2594636f06f386e53f128dfd0246963eeba88a5aa262e1f1e5ce144a73584b3b",
    "Mpv": "5792d0cc760362398f60ede3a170a309a80ac7dab30ff5b8f962f0eec10dab32",
    "Png16": "d7a802f20be9203d82ea31937b8eca0069d3df33f78f63de475955c02a698fd1",
    "Swresample": "6b827a24e7b4d66937bb0c96b269af2762e6ec922d23efda184af5d85728ed52",
    "Swscale": "0becbde38e457eff9fabf681b8df038904a6e1d367f43f74155a80eb3759c9ac",
    "Uchardet": "e6c651adff7ab2c37ec592b5f1bb15d0cd0e6b4415792798de55c7f4be74820a",
    "Xml2": "6e4181b7772a41cd7e945a7bac312002949492c7b7e63de50b325c21e79e24ee"
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
