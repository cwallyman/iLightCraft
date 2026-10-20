//
//  DevelopMergeSettings.swift
//  Unveil
//

/// DevelopMergeSettings is a partial `DevelopSettings` for `develop.merge`: only the groups that
/// are present change, the rest of the photo's settings stay as they are. Reset All uses it to put
/// back what `Photo::camera_defaults` adds on top of `develop.reset`'s look. The keys are snake case
/// because the engine's settings structs have no rename.
nonisolated struct DevelopMergeSettings: Encodable, Equatable, Sendable {

    let detail: Detail?
    let optics: Optics?
    var hdr: HDR? = nil

    struct HDR: Encodable, Equatable, Sendable {

        let enabled: Bool
        let max_ev: Double
    }

    /// none changes nothing: a photo whose import look is the reset look.
    static let none = DevelopMergeSettings(detail: nil, optics: nil)

    var isEmpty: Bool { detail == nil && optics == nil && hdr == nil }

    struct Detail: Encodable, Equatable, Sendable {

        let sharpenAmount: Double
        let nrColor      : Double

        enum CodingKeys: String, CodingKey {

            case sharpenAmount = "sharpen_amount"
            case nrColor       = "nr_color"
        }
    }

    struct Optics: Encodable, Equatable, Sendable {

        let lensProfile: Bool

        enum CodingKeys: String, CodingKey {

            case lensProfile = "lens_profile"
        }
    }
}
