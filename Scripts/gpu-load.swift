import Foundation
import Metal
// Короткая проверочная нагрузка. В приложение этот файл не включается.
let device = MTLCreateSystemDefaultDevice()!
let source = """
#include <metal_stdlib>
using namespace metal;
kernel void work(device float *output [[buffer(0)]], uint i [[thread_position_in_grid]]) {
    float v = float(i) * 0.0001f;
    for (uint j = 0; j < 256; ++j) { v = sin(v) + cos(v * 1.01f); }
    output[i] = v;
}
"""
let library = try device.makeLibrary(source: source, options: nil)
let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "work")!)
let queue = device.makeCommandQueue()!
let buffer = device.makeBuffer(length: 262144 * 4)!
let stop = Date().addingTimeInterval(8)
while Date() < stop {
    autoreleasepool {
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline); encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 262144, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256,pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
    }
}
