//
//  VirtualMemoryMap.swift
//  iLightCraft
//

import Darwin
import Foundation

/// VirtualMemoryMap walks the process's address space (`vm_region_recurse_64`) and adds up the pages
/// by the kernel's region tag, the table `vmmap` prints: malloc heaps, IOKit and IOSurface mappings
/// (what Metal buffers are), stacks, dylibs. It is how the E0 memory map names the part of
/// `phys_footprint` that no engine counter owns.
///
/// For each tag it keeps the resident, dirty, swapped (compressed) and reusable bytes. Reusable pages
/// are freed memory the allocator kept mapped: they sit in `dirty` and do not count to the footprint.
nonisolated enum VirtualMemoryMap {

    struct Total: Sendable {

        var regions : Int    = 0
        var virtual : UInt64 = 0
        var resident: UInt64 = 0
        var dirty   : UInt64 = 0
        var swapped : UInt64 = 0
        var reusable: UInt64 = 0
    }

    private static let names: [Int32: String] = [
        VM_MEMORY_MALLOC               : "MALLOC",
        VM_MEMORY_MALLOC_SMALL         : "MALLOC_SMALL",
        VM_MEMORY_MALLOC_LARGE         : "MALLOC_LARGE",
        VM_MEMORY_MALLOC_HUGE          : "MALLOC_HUGE",
        VM_MEMORY_MALLOC_TINY          : "MALLOC_TINY",
        VM_MEMORY_MALLOC_LARGE_REUSABLE: "MALLOC_LARGE_REUSABLE",
        VM_MEMORY_MALLOC_LARGE_REUSED  : "MALLOC_LARGE_REUSED",
        VM_MEMORY_MALLOC_NANO          : "MALLOC_NANO",
        VM_MEMORY_MALLOC_MEDIUM        : "MALLOC_MEDIUM",
        VM_MEMORY_IOKIT                : "IOKit",
        VM_MEMORY_IOSURFACE            : "IOSurface",
        VM_MEMORY_STACK                : "Stack",
        VM_MEMORY_GUARD                : "Guard",
        VM_MEMORY_DYLIB                : "Dylib",
        VM_MEMORY_COREGRAPHICS         : "CoreGraphics",
        VM_MEMORY_COREGRAPHICS_DATA    : "CoreGraphics data",
        VM_MEMORY_COREGRAPHICS_BACKINGSTORES: "CoreGraphics backing",
        VM_MEMORY_CGIMAGE              : "CGImage",
        VM_MEMORY_IMAGEIO              : "ImageIO",
        VM_MEMORY_LAYERKIT             : "LayerKit",
        VM_MEMORY_FOUNDATION           : "Foundation",
        VM_MEMORY_SWIFT_RUNTIME        : "Swift runtime",
        VM_MEMORY_SWIFT_METADATA       : "Swift metadata",
        VM_MEMORY_COREUI               : "CoreUI",
        VM_MEMORY_SQLITE               : "SQLite",
        VM_MEMORY_OS_ALLOC_ONCE        : "os_alloc_once",
        VM_MEMORY_LIBDISPATCH          : "libdispatch",
        VM_MEMORY_DYLD                 : "dyld",
        VM_MEMORY_DYLD_MALLOC          : "dyld malloc",
        VM_MEMORY_SHARED_PMAP          : "shared pmap",
        VM_MEMORY_UNSHARED_PMAP        : "unshared pmap",
    ]

    /// byTag sums the regions of the address space per tag, keyed by the tag's name (or `tag N`).
    static func byTag() -> [String: Total] {
        var totals   = [String: Total]()
        var address  = vm_address_t(0)
        var depth    = natural_t(0)
        let pageSize = UInt64(getpagesize())

        while true {
            var size  = vm_size_t(0)
            var info  = vm_region_submap_info_data_64_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<vm_region_submap_info_data_64_t>.size / MemoryLayout<natural_t>.size
            )

            // vm_region_recurse_64 fills `count` words of the struct it was given.
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { words in
                    vm_region_recurse_64(mach_task_self_, &address, &size, &depth, words, &count)
                }
            }

            guard status == KERN_SUCCESS else { break }

            if info.is_submap != 0 {
                depth += 1
                continue
            }

            let tag  = Int32(info.user_tag)
            let name = names[tag] ?? "tag \(tag)"

            totals[name, default: Total()].regions  += 1
            totals[name, default: Total()].virtual  += UInt64(size)
            totals[name, default: Total()].resident += UInt64(info.pages_resident) * pageSize
            totals[name, default: Total()].dirty    += UInt64(info.pages_dirtied) * pageSize
            totals[name, default: Total()].swapped  += UInt64(info.pages_swapped_out) * pageSize
            totals[name, default: Total()].reusable += UInt64(info.pages_reusable) * pageSize

            address += size
        }

        return totals
    }
}
