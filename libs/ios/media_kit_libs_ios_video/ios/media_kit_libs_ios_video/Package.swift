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

let libmpvArtifactBase = "https://github.com/xweiba/libmpv-darwin-build/releases/download/0.6.8-mediaio.2/libmpv-xcframeworks_0.6.8-mediaio.2_ios-universal-video-default"
let libmpvChecksums = [
    "Ass": "cfe9a360cac170156f426931eeff07658ec36a9947ad7aef489ff88a6e48f85f",
    "Avcodec": "235e93cc599aaf8abf47219ae3549379b7b7cd484ee32b34b8e494fd9a579bda",
    "Avfilter": "14ef79ac988ae0df35849d5f5f85eab168027251ed164508e6cb0fab22b2896b",
    "Avformat": "e812290459a8e48d5712dfb9eab1655a59b0f789346d8fec0cf3c6a1ec6ffc64",
    "Avutil": "11f6105698dacf673877bd8218384fa70db6c7ff866b7f283287dc84f6d05cb6",
    "Dav1d": "87b809dd9eb6f56a5726052619c4d5ddcc94e638758b629890c7ab3ea1eb96b6",
    "Freetype": "92d2598bec1ee0b33080f96f7760913e7bbc527b506be52aa8576f3240b75ef6",
    "Fribidi": "9da129db2b05f915eb0b6e61663a15f9889e163c849d957bcfada7cad10cc56e",
    "Harfbuzz": "7df2839260c4d4b2c126776eda40e40ae9789a2ca76efdfbcfe336fda4997b72",
    "Mbedcrypto": "419f78fbd7acd6977704cb5aa71386cd0219c50a7a754f651b6cf7daa8b70f61",
    "Mbedtls": "796ba85d773686e51f11a21d084b83c8607beefa16ed735b3132221c74b4ea10",
    "Mbedx509": "4b12af5ff81da56ebcd532b97e9ea5daf1a2c486a759749675f1cd5e2ef9b951",
    "Mpv": "dbd7c4f4075b6b818c1b6dbaadfa6e81b47c41992ff268d04bf25fe53c96f581",
    "Png16": "2a3e9ecc2dd3538ffa88dcfb4d3eeead7784ef901fd738f781d49419aff873f5",
    "Swresample": "dde17d69da4927563cb3b8ca196821b94d255b70ab2d9ecae700ae55d7f5cef0",
    "Swscale": "2cab0cf692ea9deafc43f5cc0f3dcf337ed072946002c6f5502dbef162b9f6ef",
    "Uchardet": "5796c47ee53bbe58b3e9eeef7ef56367b7639ad8236f5e4977731226c9adb91c",
    "Xml2": "cf50939d8443a7ae92d0fdbf95d95dc9cb639f91d1ba4e457c8e3c2adc2be715"
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
