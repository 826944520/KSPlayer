


import Foundation
import Metal
import simd
#if canImport(UIKit)
import UIKit
#endif

public extension KSOptions {

    static var vrFov: Float = Float.pi / 2
}

/// Preallocated pool of per-frame vertex matrices. Sized to the maximum number
/// of frames in flight (MetalRender.draw's inflight semaphore = 3, times the
/// matrices each frame needs), so a slot is never rewritten while the GPU is
/// still reading the previous use. set(encoder:) runs on the main actor, so the
/// ring index cannot race a pending draw.
private final class MatrixBufferRing {
    private let buffers: [MTLBuffer]
    private var index = 0

    init(count: Int) {
        buffers = (0 ..< count).map { _ in
            MetalRender.device.makeBuffer(length: MemoryLayout<simd_float4x4>.size, options: [])!
        }
    }

    func next() -> MTLBuffer {
        defer { index = (index + 1) % buffers.count }
        return buffers[index]
    }
}

extension DisplayEnum {
    private static var planeDisplay = PlaneDisplayModel()
    private static var vrDiaplay = VRDisplayModel()
    private static var vrBoxDiaplay = VRBoxDisplayModel()

    func set(encoder: MTLRenderCommandEncoder) {
        switch self {
        case .plane:
            DisplayEnum.planeDisplay.set(encoder: encoder)
        case .vr:
            DisplayEnum.vrDiaplay.set(encoder: encoder)
        case .vrBox:
            DisplayEnum.vrBoxDiaplay.set(encoder: encoder)
        }
    }

    func pipeline(planeCount: Int, bitDepth: Int32) -> MTLRenderPipelineState {
        switch self {
        case .plane:
            return DisplayEnum.planeDisplay.pipeline(planeCount: planeCount, bitDepth: bitDepth)
        case .vr:
            return DisplayEnum.vrDiaplay.pipeline(planeCount: planeCount, bitDepth: bitDepth)
        case .vrBox:
            return DisplayEnum.vrBoxDiaplay.pipeline(planeCount: planeCount, bitDepth: bitDepth)
        }
    }

    func touchesMoved(touch: UITouch) {
        switch self {
        case .vr:
            DisplayEnum.vrDiaplay.touchesMoved(touch: touch)
        case .vrBox:
            DisplayEnum.vrBoxDiaplay.touchesMoved(touch: touch)
        default:
            break
        }
    }
}

private class PlaneDisplayModel {
    private lazy var yuv = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture")
    private lazy var yuvp010LE = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", bitDepth: 10)
    private lazy var nv12 = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture")
    private lazy var p010LE = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", bitDepth: 10)
    private lazy var bgra = MetalRender.makePipelineState(fragmentFunction: "displayTexture")
    let indexCount: Int
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangleStrip
    let indexBuffer: MTLBuffer
    let posBuffer: MTLBuffer?
    let uvBuffer: MTLBuffer?

    fileprivate init() {
        let (indices, positions, uvs) = PlaneDisplayModel.genSphere()
        let device = MetalRender.device
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indexCount)!
        posBuffer = device.makeBuffer(bytes: positions, length: MemoryLayout<simd_float4>.size * positions.count)
        uvBuffer = device.makeBuffer(bytes: uvs, length: MemoryLayout<simd_float2>.size * uvs.count)
    }

    private static func genSphere() -> ([UInt16], [simd_float4], [simd_float2]) {
        let indices: [UInt16] = [0, 1, 2, 3]
        let positions: [simd_float4] = [
            [-1.0, -1.0, 0.0, 1.0],
            [-1.0, 1.0, 0.0, 1.0],
            [1.0, -1.0, 0.0, 1.0],
            [1.0, 1.0, 0.0, 1.0],
        ]
        let uvs: [simd_float2] = [
            [0.0, 1.0],
            [0.0, 0.0],
            [1.0, 1.0],
            [1.0, 0.0],
        ]
        return (indices, positions, uvs)
    }

    func set(encoder: MTLRenderCommandEncoder) {
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }

    func pipeline(planeCount: Int, bitDepth: Int32) -> MTLRenderPipelineState {
        switch planeCount {
        case 3:
            if bitDepth == 10 {
                return yuvp010LE
            } else {
                return yuv
            }
        case 2:
            if bitDepth == 10 {
                return p010LE
            } else {
                return nv12
            }
        case 1:
            return bgra
        default:
            return bgra
        }
    }
}

@MainActor
private class SphereDisplayModel {
    private lazy var yuv = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true)
    private lazy var yuvp010LE = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: true, bitDepth: 10)
    private lazy var nv12 = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true)
    private lazy var p010LE = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: true, bitDepth: 10)
    private lazy var bgra = MetalRender.makePipelineState(fragmentFunction: "displayTexture", isSphere: true)
    private var fingerRotationX = Float(0)
    private var fingerRotationY = Float(0)
    fileprivate var modelViewMatrix = matrix_identity_float4x4
    let indexCount: Int
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangle
    let indexBuffer: MTLBuffer
    let posBuffer: MTLBuffer?
    let uvBuffer: MTLBuffer?
    @MainActor
    fileprivate init() {
        let (indices, positions, uvs) = SphereDisplayModel.genSphere()
        let device = MetalRender.device
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indexCount)!
        posBuffer = device.makeBuffer(bytes: positions, length: MemoryLayout<simd_float4>.size * positions.count)
        uvBuffer = device.makeBuffer(bytes: uvs, length: MemoryLayout<simd_float2>.size * uvs.count)
        #if canImport(UIKit) && canImport(CoreMotion)
        if KSOptions.enableSensor {
            MotionSensor.shared.start()
        }
        #endif
    }

    func set(encoder: MTLRenderCommandEncoder) {
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        #if canImport(UIKit) && canImport(CoreMotion)
        if KSOptions.enableSensor, let matrix = MotionSensor.shared.matrix() {
            modelViewMatrix = matrix
        }
        #endif
    }

    @MainActor
    func touchesMoved(touch: UITouch) {
        #if canImport(UIKit)
        let view = touch.view
        #else
        let view: UIView? = nil
        #endif
        var distX = Float(touch.location(in: view).x - touch.previousLocation(in: view).x)
        var distY = Float(touch.location(in: view).y - touch.previousLocation(in: view).y)
        distX *= 0.005
        distY *= 0.005
        fingerRotationX -= distY * 60 / 100
        fingerRotationY -= distX * 60 / 100
        modelViewMatrix = matrix_identity_float4x4.rotateX(radians: fingerRotationX).rotateY(radians: fingerRotationY)
    }

    func reset() {
        fingerRotationX = 0
        fingerRotationY = 0
        modelViewMatrix = matrix_identity_float4x4
    }

    private static func genSphere() -> ([UInt16], [simd_float4], [simd_float2]) {
        let slicesCount = UInt16(200)
        let parallelsCount = slicesCount / 2
        let indicesCount = Int(slicesCount) * Int(parallelsCount) * 6
        var indices = [UInt16](repeating: 0, count: indicesCount)
        var positions = [simd_float4]()
        var uvs = [simd_float2]()
        var runCount = 0
        let radius = Float(1.0)
        let step = (2.0 * Float.pi) / Float(slicesCount)
        var i = UInt16(0)
        while i <= parallelsCount {
            var j = UInt16(0)
            while j <= slicesCount {
                let vertex0 = radius * sinf(step * Float(i)) * cosf(step * Float(j))
                let vertex1 = radius * cosf(step * Float(i))
                let vertex2 = radius * sinf(step * Float(i)) * sinf(step * Float(j))
                let vertex3 = Float(1.0)
                let vertex4 = Float(j) / Float(slicesCount)
                let vertex5 = Float(i) / Float(parallelsCount)
                positions.append([vertex0, vertex1, vertex2, vertex3])
                uvs.append([vertex4, vertex5])
                if i < parallelsCount, j < slicesCount {
                    indices[runCount] = i * (slicesCount + 1) + j
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + j)
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + (j + 1))
                    runCount += 1
                    indices[runCount] = UInt16(i * (slicesCount + 1) + j)
                    runCount += 1
                    indices[runCount] = UInt16((i + 1) * (slicesCount + 1) + (j + 1))
                    runCount += 1
                    indices[runCount] = UInt16(i * (slicesCount + 1) + (j + 1))
                    runCount += 1
                }
                j += 1
            }
            i += 1
        }
        return (indices, positions, uvs)
    }

    func pipeline(planeCount: Int, bitDepth: Int32) -> MTLRenderPipelineState {
        switch planeCount {
        case 3:
            if bitDepth == 10 {
                return yuvp010LE
            } else {
                return yuv
            }
        case 2:
            if bitDepth == 10 {
                return p010LE
            } else {
                return nv12
            }
        case 1:
            return bgra
        default:
            return bgra
        }
    }
}

private class VRDisplayModel: SphereDisplayModel {

    private var modelViewProjectionMatrix: simd_float4x4 {
        let size = KSOptions.sceneSize
        let aspect = Float(size.width / size.height)
        let projectionMatrix = simd_float4x4(perspective: KSOptions.vrFov, aspect: aspect, nearZ: 0.1, farZ: 400.0)
        let viewMatrix = simd_float4x4(lookAt: SIMD3<Float>.zero, center: [0, 0, -1000], up: [0, 1, 0])
        return projectionMatrix * viewMatrix
    }

    // Ring sized to one renderer's in-flight budget (3 = MetalRender's
    // inflightSemaphore). The display models are process-wide singletons, so if
    // two+ VR layers render concurrently each can hold 3 frames while the shared
    // ring has only 3 slots — a slot could be overwritten while an earlier
    // renderer's GPU pass still reads it (rare, cosmetic geometry tearing).
    // Acceptable for the single-active-VR-player case; revisit if multi-player
    // VR matters.
    private let matrixBufferRing = MatrixBufferRing(count: 3)

    override required init() {
        super.init()
    }

    override func set(encoder: MTLRenderCommandEncoder) {
        super.set(encoder: encoder)
        let matrixBuffer = matrixBufferRing.next()
        var matrix = modelViewProjectionMatrix * modelViewMatrix
        matrixBuffer.contents().copyMemory(from: &matrix, byteCount: MemoryLayout<simd_float4x4>.size)
        encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 2)
        encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }
}

private class VRBoxDisplayModel: SphereDisplayModel {

    private var modelViewProjectionMatrixLeft: simd_float4x4 {
        let size = KSOptions.sceneSize
        let aspect = Float(size.width / size.height) / 2
        let viewMatrixLeft = simd_float4x4(lookAt: [-0.012, 0, 0], center: [0, 0, -1000], up: [0, 1, 0])
        let projectionMatrix = simd_float4x4(perspective: KSOptions.vrFov, aspect: aspect, nearZ: 0.1, farZ: 400.0)
        return projectionMatrix * viewMatrixLeft
    }

    private var modelViewProjectionMatrixRight: simd_float4x4 {
        let size = KSOptions.sceneSize
        let aspect = Float(size.width / size.height) / 2
        let viewMatrixRight = simd_float4x4(lookAt: [0.012, 0, 0], center: [0, 0, -1000], up: [0, 1, 0])
        let projectionMatrix = simd_float4x4(perspective: KSOptions.vrFov, aspect: aspect, nearZ: 0.1, farZ: 400.0)
        return projectionMatrix * viewMatrixRight
    }

    private let matrixBufferRing = MatrixBufferRing(count: 6)

    override required init() {
        super.init()
    }

    override func set(encoder: MTLRenderCommandEncoder) {
        super.set(encoder: encoder)
        let layerSize = KSOptions.sceneSize
        let width = Double(layerSize.width / 2)
        [(modelViewProjectionMatrixLeft, MTLViewport(originX: 0, originY: 0, width: width, height: Double(layerSize.height), znear: 0, zfar: 0)),
         (modelViewProjectionMatrixRight, MTLViewport(originX: width, originY: 0, width: width, height: Double(layerSize.height), znear: 0, zfar: 0))].forEach { modelViewProjectionMatrix, viewport in
            encoder.setViewport(viewport)
            let matrixBuffer = matrixBufferRing.next()
            var matrix = modelViewProjectionMatrix * modelViewMatrix
            matrixBuffer.contents().copyMemory(from: &matrix, byteCount: MemoryLayout<simd_float4x4>.size)
            encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 2)
            encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }
    }
}
