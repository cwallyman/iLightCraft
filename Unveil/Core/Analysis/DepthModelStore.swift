//
//  DepthModelStore.swift
//  Unveil
//

import Foundation
import CryptoKit
import CoreML

/// DepthModelStore installs only the pinned Apache-2.0 small depth model after a user action.
nonisolated enum DepthModelStore {
    static let revision = "cfef6f6f2a70783dedc0bfae40cecbc2052285d3"
    static let modelPage = "https://huggingface.co/apple/coreml-depth-anything-v2-small"
    static let directory = URL.applicationSupportDirectory.appending(path: "Models/DepthAnythingV2SmallF16", directoryHint: .isDirectory)
    static var installed: URL? {
        let url = directory.appending(path: "DepthAnything.mlmodelc")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    struct File: Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }
    static let files = [
        File(path: "Manifest.json", size: 617, sha256: "2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7"),
        File(path: "Data/com.apple.CoreML/model.mlmodel", size: 399433, sha256: "44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042"),
        File(path: "Data/com.apple.CoreML/weights/weight.bin", size: 49419072, sha256: "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed")
    ]
    enum ModelError: Error, LocalizedError {
        case invalidDownload, insufficientMemory, notInstalled
        var errorDescription: String? {
            switch self {
            case .invalidDownload: "The model download did not match its pinned size and SHA-256. It was not installed."
            case .insufficientMemory: "Free more memory before compiling or using the depth model."
            case .notInstalled: "Download the on-device depth model first."
            }
        }
    }
    static func install(progress: @escaping @Sendable (String) -> Void) async throws {
        if installed != nil { return }
        let fm = FileManager.default
        let staging = directory.deletingLastPathComponent().appending(path: "depth-install-\(UUID())")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let package = staging.appending(path: "DepthAnythingV2SmallF16.mlpackage")
        for file in files {
            try Task.checkCancellation()
            progress(file.path.hasSuffix("weight.bin") ? "Downloading 49 MB model weights…" : "Downloading model specification…")
            let address = "\(modelPage)/resolve/\(revision)/DepthAnythingV2SmallF16.mlpackage/\(file.path)"
            guard let url = URL(string: address) else { throw ModelError.invalidDownload }
            let limit = BoundedModelDownload(limit: file.size)
            let (temporary, response) = try await URLSession.shared.download(from: url, delegate: limit)
            defer { try? fm.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value == file.size,
                  try sha256(temporary) == file.sha256 else { throw ModelError.invalidDownload }
            let target = package.appending(path: file.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temporary, to: target)
        }
        try Task.checkCancellation()
        let available = ProcessAvailableMemory().availableBytes()
        guard available >= 700 * 1024 * 1024 else { throw ModelError.insufficientMemory }
        progress("Compiling for this device…")
        let compiled = try await Task.detached(priority: .userInitiated) { try MLModel.compileModel(at: package) }.value
        defer { try? fm.removeItem(at: compiled) }
        try Task.checkCancellation()
        let final = staging.appending(path: "installed", directoryHint: .isDirectory)
        try fm.createDirectory(at: final, withIntermediateDirectories: true)
        try fm.copyItem(at: compiled, to: final.appending(path: "DepthAnything.mlmodelc"))
        guard let licence = Bundle.main.url(forResource: "Model-LICENSE-APACHE", withExtension: "txt") else { throw ModelError.invalidDownload }
        try fm.copyItem(at: licence, to: final.appending(path: "LICENSE.txt"))
        let notice = "Depth Anything V2 Small by Lihe Yang and collaborators; Core ML conversion published by Apple. Apache-2.0. Source: \(modelPage), revision \(revision). Weights verified by SHA-256. No photo uploads.\n"
        try Data(notice.utf8).write(to: final.appending(path: "SOURCE.txt"), options: .atomic)
        if fm.fileExists(atPath: directory.path) { throw ModelError.invalidDownload }
        try fm.moveItem(at: final, to: directory)
        progress("Depth model installed. Processing stays on device.")
    }
    static func remove() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
