//
//  PhotosExportRequest.swift
//  iLightCraft
//

nonisolated struct PhotosExportRequest: Encodable, Sendable {

    let id: UInt64
    let path: String
    let format = "jpeg"
    let quality = 100
    let longEdge = 0
    let colorSpace = "srgb"
}
