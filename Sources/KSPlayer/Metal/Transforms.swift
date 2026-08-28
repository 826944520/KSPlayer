


import simd


extension simd_float4x4 {
    static let identity = matrix_identity_float4x4


    init(scale x: Float, y: Float, z: Float) {
        self.init(diagonal: [x, y, z, 1.0])
    }


    init(translate: SIMD3<Float>) {
        self.init([1, 0.0, 0.0, translate.x],
                  [0.0, 1, 0.0, translate.y],
                  [0.0, 0.0, 1, translate.z],
                  [0.0, 0.0, 0, 1])
    }

    init(rotationX radians: Float) {
        let cos = cosf(radians)
        let sin = sinf(radians)
        self.init([1, 0.0, 0.0, 0],
                  [0.0, cos, sin, 0],
                  [0.0, -sin, cos, 0],
                  [0.0, 0.0, 0, 1])
    }

    init(rotationY radians: Float) {
        let cos = cosf(radians)
        let sin = sinf(radians)
        self.init([cos, 0.0, -sin, 0],
                  [0.0, 1, 0, 0],
                  [sin, 0, cos, 0],
                  [0.0, 0.0, 0, 1])
    }

    init(rotationZ radians: Float) {
        let cos = cosf(radians)
        let sin = sinf(radians)
        self.init([cos, sin, 0.0, 0],
                  [-sin, cos, 0, 0],
                  [0.0, 0, 1, 0],
                  [0.0, 0.0, 0, 1])
    }

    public init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        let N = normalize(eye - center)
        let U = normalize(cross(up, N))
        let V = cross(N, U)
        // Fix: Build standard view matrix with eye offset in last column (not last row)
        // Column-major: [U.x, U.y, U.z, -dot(U,eye)], [V.x, V.y, V.z, -dot(V,eye)], ...
        self.init(columns: [[U.x, U.y, U.z, -dot(U, eye)],
                            [V.x, V.y, V.z, -dot(V, eye)],
                            [N.x, N.y, N.z, -dot(N, eye)],
                            [0.0, 0.0, 0.0, 1.0]])
    }

    public init(perspective fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) {
        let cotan = 1.0 / tanf(fovyRadians / 2.0)
        self.init([cotan / aspect, 0.0, 0.0, 0.0],
                  [0.0, cotan, 0.0, 0.0],
                  [0.0, 0.0, (farZ + nearZ) / (nearZ - farZ), -1],
                  [0.0, 0.0, (2.0 * farZ * nearZ) / (nearZ - farZ), 0])
    }

    public init(euler x: Float, y: Float, z: Float) {
        let x = x * .pi / 180
        let y = y * .pi / 180
        let z = z * .pi / 180
        let cx = cos(x)
        let sx = sin(x)
        let cy = cos(y)
        let sy = sin(y)
        let cz = cos(z)
        let sz = sin(z)
        let cxsy = cx * sy
        let sxsy = sx * sy
        self.init([cy * cz, -cy * sz, sy, 0.0],
                  [cxsy * cz + cx * sz, -cxsy * sz + cx * cz, -sx * cy, 0.0],
                  [-sxsy * cz + sx * sz, sxsy * sz + sx * cz, cx * cy, 0],
                  [0.0, 0.0, 0, 1])
    }

    func rotateX(radians: Float) -> simd_float4x4 {
        self * simd_float4x4(rotationX: radians)
    }

    func rotateY(radians: Float) -> simd_float4x4 {
        self * simd_float4x4(rotationY: radians)
    }

    func rotateZ(radians: Float) -> simd_float4x4 {
        self * simd_float4x4(rotationZ: radians)
    }
}


