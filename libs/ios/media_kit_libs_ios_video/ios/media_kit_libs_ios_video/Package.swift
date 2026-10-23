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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.7/libmpv-xcframeworks_0.6.8-mediaio.7_ios-universal-video-default"
let libmpvChecksums = [
    "Ass": "9b415083b4e221ed9fd6fb166e23023e848d3fcfbecef32b761848c6eff94c60",
    "Avcodec": "e5e5600664881d6c29946d0ae2ca3a301ab949aa874d7fee088892b61abc0285",
    "Avfilter": "30f89b416fd57f18ba7d3c369d4e1fc05ef36fdded8cda1bb1975fca8bfda592",
    "Avformat": "d6c6cec3fcfc96670e9d8971afd463e90e5b4ac1ffa9f8fecea1104d55a957c3",
    "Avutil": "22f4d63b718c0c67935109aa48d029d10a87a5c02a401f3488e481041d7ec19f",
    "Dav1d": "e4f61a452b32e4c14d59f37b035cf1420d06d7c1a9037aad33dd0da4dbf319e1",
    "Freetype": "81579c496d4a59c020d1fad2629b56efd163bbbe1bd62986b9abdbe558ab307b",
    "Fribidi": "0e2d49b59830c2ce2d37ac90206903ab94cb01b98cc876b7d817be5412d0ff7f",
    "Harfbuzz": "251e2002dd96e32b1a4e492216db99dd1b6f873a90944a1e7c8a4d21b8dd05f7",
    "Mbedcrypto": "4074bc9e5c93ec830b6c6ba9f44390c6c4779e3e7656929b936493c4ebcdc9e8",
    "Mbedtls": "64be897d8d8c3773f95dfa815964f2a1440bc71dbdee30491f210d69e02c18a2",
    "Mbedx509": "ea03f4e857f1ecaf8ad8abb6de274147e7f2b61d5a4bba30b59629f76d59ce8a",
    "Mpv": "d2383e26ec823886850b09b2582093aa8e00ed92471d8bc8477560943c8ce0f6",
    "Png16": "1288e162b9fb730a8196cf420e230d8b8d1428696bbdb2a96ee96fecb7240a64",
    "Swresample": "190ce9f43bdbd870fbf6fb8a5e16ac9c851e24285242e369305589e033889a82",
    "Swscale": "fea008950136f83c87956a47f3f98c355cdc3e6e5dd0d70bb61faddb08c9f58c",
    "Uchardet": "96c868019667729e1b62ec5a5017d8bf71a2a541d6fd5957cf1a9892ee745ee4",
    "Xml2": "9c3037c2131a2dd61b507b3bea5f95fdab161ab178be4561096fbfb70e2160b5"
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
