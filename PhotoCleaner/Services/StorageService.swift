import Foundation

enum StorageService {
    static func snapshot() -> StorageSnapshot {
        do {
            let url = URL(fileURLWithPath: "/")
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            return StorageSnapshot(
                totalBytes: values.volumeTotalCapacity.map(Int64.init),
                availableBytes: values.volumeAvailableCapacityForImportantUsage
            )
        } catch {
            return StorageSnapshot(totalBytes: nil, availableBytes: nil)
        }
    }
}
