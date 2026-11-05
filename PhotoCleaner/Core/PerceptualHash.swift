import CoreGraphics
import Foundation

public struct ImageFingerprint: Hashable, Codable, Sendable {
    public let differenceHash: UInt64
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(differenceHash: UInt64, red: UInt8, green: UInt8, blue: UInt8) {
        self.differenceHash = differenceHash
        self.red = red
        self.green = green
        self.blue = blue
    }

    public func colorDistance(to other: ImageFingerprint) -> Int {
        abs(Int(red) - Int(other.red)) +
        abs(Int(green) - Int(other.green)) +
        abs(Int(blue) - Int(other.blue))
    }

    public func hammingDistance(to other: ImageFingerprint) -> Int {
        (differenceHash ^ other.differenceHash).nonzeroBitCount
    }
}

public struct FingerprintedAsset: Sendable {
    public let id: String
    public let fingerprint: ImageFingerprint
    public let burstIdentifier: String?

    public init(id: String, fingerprint: ImageFingerprint, burstIdentifier: String? = nil) {
        self.id = id
        self.fingerprint = fingerprint
        self.burstIdentifier = burstIdentifier
    }
}

public enum PerceptualHasher {
    public static func fingerprint(_ image: CGImage) -> ImageFingerprint? {
        let width = 9
        let height = 8
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var luminance = [Int](repeating: 0, count: width * height)
        var red = 0
        var green = 0
        var blue = 0

        for pixel in 0..<(width * height) {
            let offset = pixel * bytesPerPixel
            let r = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let b = Int(pixels[offset + 2])
            red += r
            green += g
            blue += b
            luminance[pixel] = (r * 299 + g * 587 + b * 114) / 1000
        }

        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if luminance[y * width + x] > luminance[y * width + x + 1] {
                    hash |= UInt64(1) << UInt64(y * (width - 1) + x)
                }
            }
        }

        let pixelCount = width * height
        return ImageFingerprint(
            differenceHash: hash,
            red: UInt8(red / pixelCount),
            green: UInt8(green / pixelCount),
            blue: UInt8(blue / pixelCount)
        )
    }
}

public enum DuplicateGrouper {
    public static func groups(
        from assets: [FingerprintedAsset],
        hammingThreshold: Int = 5,
        colorThreshold: Int = 120
    ) -> [[String]] {
        guard assets.count > 1 else { return [] }

        var unionFind = UnionFind(count: assets.count)
        var tree = BKTree()

        for (index, asset) in assets.enumerated() {
            for candidateIndex in tree.matches(for: asset.fingerprint.differenceHash, radius: hammingThreshold) {
                let candidate = assets[candidateIndex]
                guard asset.fingerprint.colorDistance(to: candidate.fingerprint) <= colorThreshold else { continue }
                unionFind.join(index, candidateIndex)
            }
            tree.insert(asset.fingerprint.differenceHash, index: index)
        }

        var bursts: [String: [Int]] = [:]
        for (index, asset) in assets.enumerated() {
            guard let burstIdentifier = asset.burstIdentifier else { continue }
            bursts[burstIdentifier, default: []].append(index)
        }
        for indices in bursts.values where indices.count > 1 {
            for index in indices.dropFirst() {
                unionFind.join(indices[0], index)
            }
        }

        var groups: [Int: [String]] = [:]
        for index in assets.indices {
            groups[unionFind.root(of: index), default: []].append(assets[index].id)
        }
        return groups.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }
}

private struct BKTree {
    private final class Node {
        let value: UInt64
        var indices: [Int]
        var children: [Int: Node] = [:]

        init(value: UInt64, index: Int) {
            self.value = value
            self.indices = [index]
        }
    }

    private var root: Node?

    mutating func insert(_ value: UInt64, index: Int) {
        guard let root else {
            self.root = Node(value: value, index: index)
            return
        }
        insert(value, index: index, into: root)
    }

    func matches(for value: UInt64, radius: Int) -> [Int] {
        guard let root else { return [] }
        var result: [Int] = []
        collectMatches(value, radius: radius, in: root, into: &result)
        return result
    }

    private func insert(_ value: UInt64, index: Int, into node: Node) {
        let distance = (value ^ node.value).nonzeroBitCount
        if distance == 0 {
            node.indices.append(index)
        } else if let child = node.children[distance] {
            insert(value, index: index, into: child)
        } else {
            node.children[distance] = Node(value: value, index: index)
        }
    }

    private func collectMatches(_ value: UInt64, radius: Int, in node: Node, into result: inout [Int]) {
        let distance = (value ^ node.value).nonzeroBitCount
        if distance <= radius {
            result.append(contentsOf: node.indices)
        }
        for (edge, child) in node.children where edge >= distance - radius && edge <= distance + radius {
            collectMatches(value, radius: radius, in: child, into: &result)
        }
    }
}

private struct UnionFind {
    private var parents: [Int]
    private var ranks: [Int]

    init(count: Int) {
        parents = Array(0..<count)
        ranks = Array(repeating: 0, count: count)
    }

    mutating func root(of item: Int) -> Int {
        if parents[item] != item {
            parents[item] = root(of: parents[item])
        }
        return parents[item]
    }

    mutating func join(_ lhs: Int, _ rhs: Int) {
        let leftRoot = root(of: lhs)
        let rightRoot = root(of: rhs)
        guard leftRoot != rightRoot else { return }

        if ranks[leftRoot] < ranks[rightRoot] {
            parents[leftRoot] = rightRoot
        } else if ranks[leftRoot] > ranks[rightRoot] {
            parents[rightRoot] = leftRoot
        } else {
            parents[rightRoot] = leftRoot
            ranks[leftRoot] += 1
        }
    }
}
