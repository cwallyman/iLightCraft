//
//  PhotoInfo.swift
//  iLightCraft
//

import CoreGraphics

/// PhotoInfo is the part of `photo.inspect` the editor reads: the pixel size and the facts that
/// decide the photo's own develop defaults (the catalog `Photo`, serialized in snake case).
nonisolated struct PhotoInfo: Decodable, Sendable {

    let width          : Double
    let height         : Double
    let kind           : String
    let format         : String
    let asShotWB       : [Double]?
    let previewOnly    : String?
    let hasEmbeddedLens: Bool

    /// capture is the exposure the file records (ISO, shutter, aperture, focal length), if any.
    var capture        : PhotoCapture? = nil

    enum CodingKeys: String, CodingKey {

        case width
        case height
        case kind
        case format
        case asShotWB     = "as_shot_wb"
        case previewOnly  = "preview_only"
        case embeddedLens = "embedded_lens"
        case capture      = "meta"
    }

    /// rawDetail is what `DevelopSettings::for_raw` (Engine/crates/develop/src/lib.rs:24) sets on
    /// top of the control defaults for a raw. Keep the two in step.
    static let rawDetail = DevelopMergeSettings.Detail(sharpenAmount: 40, nrColor: 25)

    static let rawDetailDefaults: [DevelopAdjustmentKind: Double] = [
        .sharpening: rawDetail.sharpenAmount,
        .colorNoise: rawDetail.nrColor,
    ]

    /// relativeWBFormats mirrors `Photo::relative_wb` (Engine/crates/catalog/src/model.rs): these
    /// raws start from 6500 K / 0 instead of the camera's as-shot numbers.
    private static let relativeWBFormats: Set<String> = [
        "ARW", "NEF", "NRW", "RW2", "RWL", "RAW", "RAF", "CR3", "CR2", "PEF",
    ]

    var size: CGSize { CGSize(width: width, height: height) }

    /// isRaw is true when import gives the photo the raw look (`Photo::camera_defaults` calls
    /// `for_raw`): a raw developed from its sensor data, or any photo with an as-shot white balance.
    var isRaw: Bool { rawWhiteBalance != nil }

    /// developDefaults is each control's value right after import, mirroring `camera_defaults`: a raw
    /// starts from its white balance plus `rawDetailDefaults`, anything else from the control defaults.
    /// A user default preset (`import_look`) is not mirrored: the app never sets one.
    var developDefaults: [DevelopAdjustmentKind: Double] {
        var defaults = Dictionary(
            uniqueKeysWithValues: DevelopAdjustmentKind.allCases.map { ($0, $0.defaultValue) }
        )

        guard let whiteBalance = rawWhiteBalance else { return defaults }

        defaults[.temperature] = whiteBalance.temp
        defaults[.tint]        = whiteBalance.tint
        defaults.merge(Self.rawDetailDefaults) { _, raw in raw }

        return defaults
    }

    /// cameraDefaultsMerge is what `Photo::camera_defaults` (Engine/crates/catalog/src/model.rs) gives
    /// the photo beyond `develop.reset`'s look (As Shot white balance, every other setting at its
    /// default): the raw detail of `for_raw`, and lens profile corrections when the file embeds them.
    var cameraDefaultsMerge: DevelopMergeSettings {
        DevelopMergeSettings(
            detail: isRaw ? Self.rawDetail : nil,
            optics: hasEmbeddedLens ? DevelopMergeSettings.Optics(lensProfile: true) : nil
        )
    }

    private var rawWhiteBalance: (temp: Double, tint: Double)? {
        let developsRaw = kind == "raw" && previewOnly == nil

        if developsRaw, Self.relativeWBFormats.contains(format.uppercased()) {
            return (6500, 0)
        }

        guard let asShotWB, asShotWB.count == 2 else { return nil }

        return (asShotWB[0], asShotWB[1])
    }
}

extension PhotoInfo {

    /// init(from:) reads `embedded_lens` only for its presence: the engine leaves the field out
    /// when the file has no lens corrections, and the editor never needs their numbers. The
    /// `any Decoder` is Decodable's own requirement.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        width           = try container.decode(Double.self, forKey: .width)
        height          = try container.decode(Double.self, forKey: .height)
        kind            = try container.decode(String.self, forKey: .kind)
        format          = try container.decode(String.self, forKey: .format)
        asShotWB        = try container.decodeIfPresent([Double].self, forKey: .asShotWB)
        previewOnly     = try container.decodeIfPresent(String.self, forKey: .previewOnly)
        // decodeNil throws for a missing key, so both absent and null read as no lens.
        hasEmbeddedLens = (try? container.decodeNil(forKey: .embeddedLens)) == false
        // Metadata is only shown: a meta the editor cannot read leaves the summary out, not the photo.
        capture         = try? container.decodeIfPresent(PhotoCapture.self, forKey: .capture)
    }
}
