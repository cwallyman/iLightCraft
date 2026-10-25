//
//  PhotoInfo+Fixtures.swift
//  iLightCraftTests
//

@testable import iLightCraft

/// Fixtures of `photo.inspect` results: a plain image, a Fujifilm raw like DSCF0267.RAF and a DNG
/// with embedded lens corrections.
extension PhotoInfo {

    static let image = PhotoInfo(
        width           : 4032,
        height          : 3024,
        kind            : "image",
        format          : "JPG",
        asShotWB        : nil,
        previewOnly     : nil,
        hasEmbeddedLens : false
    )

    static let raf = PhotoInfo(
        width           : 6240,
        height          : 4160,
        kind            : "raw",
        format          : "RAF",
        asShotWB        : [5200, 4],
        previewOnly     : nil,
        hasEmbeddedLens : false
    )

    /// A DNG with embedded lens corrections and an as-shot white balance, like an iPhone ProRAW.
    static let dngWithLens = PhotoInfo(
        width           : 4032,
        height          : 3024,
        kind            : "raw",
        format          : "DNG",
        asShotWB        : [5600, 2],
        previewOnly     : nil,
        hasEmbeddedLens : true
    )
}
