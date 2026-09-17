// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Portapapeles",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Portapapeles", targets: ["Portapapeles"]),
        // Producto propio para que Xcode le cree un esquema: las previews se
        // compilan con él.
        .library(name: "PortapapelesKit", targets: ["PortapapelesKit"])
    ],
    targets: [
        // Todo el código de la app. Va en una librería porque Xcode no renderiza
        // #Preview dentro de un target ejecutable de SwiftPM.
        .target(
            name: "PortapapelesKit",
            path: "Sources/PortapapelesKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Portapapeles",
            dependencies: ["PortapapelesKit"],
            path: "Sources/Portapapeles",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PortapapelesKitTests",
            dependencies: ["PortapapelesKit"],
            path: "Tests/PortapapelesKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
