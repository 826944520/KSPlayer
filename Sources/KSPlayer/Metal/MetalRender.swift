

import Accelerate
import CoreVideo
import Foundation
import Metal
import QuartzCore
import simd

class MetalRender {
    static let device: MTLDevice = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal device means rendering cannot proceed; log before the
            // fatal so the crash report carries the cause.
            KSLog(level: .fatal, "[metal] MTLCreateSystemDefaultDevice returned nil — Metal unavailable")
            fatalError("KSPlayer requires Metal: MTLCreateSystemDefaultDevice() returned nil")
        }
        return device
    }()

    private static let textureCache: CVMetalTextureCache? = {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, MetalRender.device, nil, &cache)
        return cache
    }()
    static let library: MTLLibrary = {
        var library: MTLLibrary!
        library = device.makeDefaultLibrary()
        if library == nil {
            library = try? device.makeDefaultLibrary(bundle: .module)
        }
        if library == nil {
            KSLog(level: .error, "[metal] makeDefaultLibrary returned nil — default shaders unavailable")
        }
        return library
    }()

    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private let commandQueue = MetalRender.device.makeCommandQueue()
    // Bounds the number of command buffers in flight to maximumDrawableCount (see
    // MetalView.init). A slow GPU throttles the CPU via this semaphore instead of
    // stalling the main thread on waitUntilCompleted() every frame.
    private let inflightSemaphore = DispatchSemaphore(value: 3)
    // Per-renderer (per-MetalView) vertex-matrix pool, so concurrent renderers
    // never share a ring. 6 slots = max matrices per frame (VRBox: 2) × frames
    // in flight (3). Plane/VR use fewer; unused slots are just idle memory.
    private let matrixBufferRing = MatrixBufferRing(count: 6)
    private lazy var samplerState: MTLSamplerState? = {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        return MetalRender.device.makeSamplerState(descriptor: samplerDescriptor)
    }()

    private lazy var colorConversion601VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.videoRange.buffer

    private lazy var colorConversion601FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.buffer

    private lazy var colorConversion709VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.videoRange.buffer

    private lazy var colorConversion709FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.buffer

    private lazy var colorConversionSMPTE240MVideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.videoRange.buffer

    private lazy var colorConversionSMPTE240MFullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.buffer

    private lazy var colorConversion2020VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.videoRange.buffer

    private lazy var colorConversion2020FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.buffer

    private lazy var colorOffsetVideoRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(-16.0 / 255.0, -128.0 / 255.0, -128.0 / 255.0)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private lazy var colorOffsetFullRangeMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<Float>(0, -128.0 / 255.0, -128.0 / 255.0)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<Float>>.size)
        buffer?.label = "colorOffset"
        return buffer
    }()

    private lazy var leftShiftMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(1, 1, 1)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    private lazy var leftShiftSixMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(64, 64, 64)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    func clear(drawable: MTLDrawable) {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            KSLog(level: .error, "[metal] clear(): commandBuffer/encoder creation failed")
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    @MainActor
    func draw(pixelBuffer: PixelBufferProtocol, display: DisplayEnum = .plane, drawable: CAMetalDrawable) {
        guard let cvPixelBuffer = pixelBuffer.cvPixelBuffer else {
            return
        }
        inflightSemaphore.wait()
        let (inputTextures, cvTextures) = MetalRender.textures(pixelBuffer: cvPixelBuffer)
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard !inputTextures.isEmpty, let commandBuffer = commandQueue?.makeCommandBuffer(), let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            KSLog(level: .error, "[metal] draw(): no inputTextures or commandBuffer/encoder creation failed (textures=\(inputTextures.count))")
            inflightSemaphore.signal()
            return
        }
        encoder.pushDebugGroup("RenderFrame")
        let transferType = Self.hdrTransferType(for: pixelBuffer)
        let state = display.pipeline(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth, transferType: transferType)
        encoder.setRenderPipelineState(state)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        setFragmentBuffer(pixelBuffer: pixelBuffer, encoder: encoder)
        if transferType != 0 {
            // The tone-mapped fragment functions read the source EOTF (1 = PQ,
            // 2 = HLG) from buffer(3) to pick the right decode curve.
            var type = transferType
            encoder.setFragmentBytes(&type, length: MemoryLayout<Int32>.size, index: 3)
        }
        display.set(encoder: encoder, ring: matrixBufferRing)
        encoder.popDebugGroup()
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // Retain the CVMetalTexture wrappers (and thus their backing IOSurface)
        // until the GPU is done sampling them. Previously waitUntilCompleted()
        // pinned them implicitly; without that barrier the IOSurface could be
        // recycled mid-draw.
        commandBuffer.addCompletedHandler { [inflightSemaphore, cvTextures] _ in
            _ = cvTextures
            inflightSemaphore.signal()
        }
    }

    private func setFragmentBuffer(pixelBuffer: PixelBufferProtocol, encoder: MTLRenderCommandEncoder) {
        if pixelBuffer.planeCount > 1 {
            let buffer: MTLBuffer?
            let yCbCrMatrix = pixelBuffer.yCbCrMatrix
            let isFullRangeVideo = pixelBuffer.isFullRangeVideo
            if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 {
                buffer = isFullRangeVideo ? colorConversion709FullRangeMatrixBuffer : colorConversion709VideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 {
                buffer = isFullRangeVideo ? colorConversionSMPTE240MFullRangeMatrixBuffer : colorConversionSMPTE240MVideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 {
                buffer = isFullRangeVideo ? colorConversion2020FullRangeMatrixBuffer : colorConversion2020VideoRangeMatrixBuffer
            } else {
                buffer = isFullRangeVideo ? colorConversion601FullRangeMatrixBuffer : colorConversion601VideoRangeMatrixBuffer
            }
            encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            let colorOffset = isFullRangeVideo ? colorOffsetFullRangeMatrixBuffer : colorOffsetVideoRangeMatrixBuffer
            encoder.setFragmentBuffer(colorOffset, offset: 0, index: 1)
            let leftShift = pixelBuffer.leftShift == 0 ? leftShiftMatrixBuffer : leftShiftSixMatrixBuffer
            encoder.setFragmentBuffer(leftShift, offset: 0, index: 2)
        }
    }

    /// Source EOTF for the tone-mapped fragment pass: 1 = PQ (ST 2084),
    /// 2 = HLG (BT.2100), 0 = none (tone-mapping off / 8-bit content).
    static func hdrTransferType(for pixelBuffer: PixelBufferProtocol) -> Int32 {
        guard KSOptions.enableToneMapping, pixelBuffer.bitDepth >= 10 else { return 0 }
        if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
            return 2
        }
        if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
            return 1
        }
        return 0
    }

    static func makePipelineState(fragmentFunction: String, isSphere: Bool = false, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)
        descriptor.vertexFunction = library.makeFunction(name: isSphere ? "mapSphereTexture" : "mapTexture")
        descriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float4>.stride
        vertexDescriptor.layouts[1].stride = MemoryLayout<simd_float2>.stride
        descriptor.vertexDescriptor = vertexDescriptor

        do {
            return try library.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            // A shader compile failure is unrecoverable for this display path;
            // log the fragment function before crashing so the remote report
            // identifies the failing pipeline.
            KSLog(level: .fatal, "[metal] makeRenderPipelineState failed fragment=\(fragmentFunction) isSphere=\(isSphere) bitDepth=\(bitDepth): \(error)")
            fatalError("KSPlayer Metal pipeline compile failed for \(fragmentFunction): \(error)")
        }
    }


    static func textures(pixelBuffer: CVPixelBuffer) -> ([MTLTexture], [CVMetalTexture]) {
        guard let textureCache else {
            return ([], [])
        }
        let formats = KSOptions.pixelFormat(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
        var textures = [MTLTexture]()
        var cvTextures = [CVMetalTexture]()
        for index in 0 ..< pixelBuffer.planeCount {
            let width = pixelBuffer.widthOfPlane(at: index)
            let height = pixelBuffer.heightOfPlane(at: index)
            var cvTexture: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, formats[index], width, height, index, &cvTexture)
            if result == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) {
                textures.append(texture)
                cvTextures.append(cvTexture)
            } else {
                KSLog(level: .error, "[metal] CVMetalTextureCacheCreateTextureFromImage failed result=\(result) plane=\(index) fmt=\(formats[index].rawValue) w=\(width) h=\(height)")
            }
        }
        return (textures, cvTextures)
    }

    static func textures(formats: [MTLPixelFormat], widths: [Int], heights: [Int], buffers: [MTLBuffer?], lineSizes: [Int]) -> [MTLTexture] {
        (0 ..< formats.count).compactMap { i in
            guard let buffer = buffers[i] else {
                return nil
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[i], width: widths[i], height: heights[i], mipmapped: false)
            descriptor.storageMode = buffer.storageMode
            return buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: lineSizes[i])
        }
    }
}


private let kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995 = vImage_YpCbCrToARGBMatrix(Kr: 0.212, Kb: 0.087)
private let kvImage_YpCbCrToARGBMatrix_ITU_R_2020 = vImage_YpCbCrToARGBMatrix(Kr: 0.2627, Kb: 0.0593)
extension vImage_YpCbCrToARGBMatrix {
    
    init(Kr: Float, Kb: Float) {
        let Kg = 1 - Kr - Kb
        self.init(Yp: 1, Cr_R: 2 - 2 * Kr, Cr_G: -Kr * (2 - 2 * Kr) / Kg, Cb_G: -Kb * (2 - 2 * Kb) / Kg, Cb_B: 2 - 2 * Kb)
    }

    var videoRange: vImage_YpCbCrToARGBMatrix {
        vImage_YpCbCrToARGBMatrix(Yp: 255 / 219 * Yp, Cr_R: 255 / 224 * Cr_R, Cr_G: 255 / 224 * Cr_G, Cb_G: 255 / 224 * Cb_G, Cb_B: 255 / 224 * Cb_B)
    }

    var buffer: MTLBuffer? {
        var matrix = simd_float3x3([Yp, Yp, Yp], [0.0, Cb_G, Cb_B], [Cr_R, Cr_G, 0.0])
        let buffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }
}


