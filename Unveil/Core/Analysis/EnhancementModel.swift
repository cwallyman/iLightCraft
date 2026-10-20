//
//  EnhancementModel.swift
//  Unveil
//

import Foundation
import CryptoKit
import CoreML

/// EnhancementModel downloads pinned BSD-3-Clause RGB restoration models, never sensor-domain RAW weights.
nonisolated enum EnhancementModel: String, CaseIterable, Sendable {
    case denoise, superResolution
    static let revision = "da0d01ce79946e6a62563eaf900ff9844af1f67f"
    static let source = "https://huggingface.co/VincentGOURBIN/RealESRGAN-CoreML"
    var package: String { self == .denoise ? "RealESRGAN-x4v3-denoise.mlpackage" : "RealESRGAN-x4v3.mlpackage" }
    var size: Int64 { self == .denoise ? 2286246 : 2286340 }
    var sha256: String {
        self == .denoise ? "a577c31ccc3025d84807f7e124d71656fb2cbbdc57c4c44d3ac2d9980da9c9c4" : "5a59e554794371b95fe61274b8a2040f1b3e274479abf15595dcdad0535afad4"
    }
    var directory: URL { URL.applicationSupportDirectory.appending(path: "Models/\(rawValue)") }
    var installed: URL? {
        let path = directory.appending(path: "Enhancement.mlmodelc")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }
    func download() async throws -> URL {
        guard let url = URL(string: "\(Self.source)/resolve/\(Self.revision)/\(package).zip") else {
            throw DepthModelStore.ModelError.invalidDownload
        }
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: BoundedModelDownload(limit: size))
        do {
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value == size else {
                throw DepthModelStore.ModelError.invalidDownload
            }
            let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard hash == sha256 else { throw DepthModelStore.ModelError.invalidDownload }
            return temporary
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
    func compile(packageURL: URL) async throws {
        guard ProcessAvailableMemory().availableBytes() >= 500 * 1024 * 1024 else {
            throw DepthModelStore.ModelError.insufficientMemory
        }
        let compiled = try await Task.detached(priority: .userInitiated) { try MLModel.compileModel(at: packageURL) }.value
        defer { try? FileManager.default.removeItem(at: compiled) }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = directory.deletingLastPathComponent().appending(path: "enhancement-install-\(UUID())")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: compiled, to: staging.appending(path: "Enhancement.mlmodelc"))
        guard let licence = Bundle.main.url(forResource: "Model-LICENSE-BSD", withExtension: "txt") else { throw DepthModelStore.ModelError.invalidDownload }
        try FileManager.default.copyItem(at: licence, to: staging.appending(path: "LICENSE.txt"))
        let provenance = "Real-ESRGAN by Xintao Wang and collaborators; Core ML conversion by VincentGOURBIN. BSD-3-Clause. \(Self.source), revision \(Self.revision), archive SHA256 \(sha256). RGB restoration, not sensor-domain Raw Details.\n"
        try Data(provenance.utf8).write(to: staging.appending(path: "SOURCE.txt"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: directory)
    }
    func remove() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
