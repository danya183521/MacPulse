import Foundation
import CoreML
import CoreVideo
// Проверка ANE использует локальную модель Apple и пустое изображение, без личных данных.
let configuration = MLModelConfiguration()
configuration.computeUnits = .cpuAndNeuralEngine
let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
let compiledURL = modelURL.pathExtension == "mlmodelc" ? modelURL : try MLModel.compileModel(at: modelURL)
let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
let input = model.modelDescription.inputDescriptionsByName.first { $0.value.type == .image }!
let constraint = input.value.imageConstraint!
var pixel: CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault, constraint.pixelsWide, constraint.pixelsHigh, constraint.pixelFormatType, nil, &pixel)
let image = pixel!
CVPixelBufferLockBaseAddress(image, [])
memset(CVPixelBufferGetBaseAddress(image), 0, CVPixelBufferGetDataSize(image))
CVPixelBufferUnlockBaseAddress(image, [])
let features = try MLDictionaryFeatureProvider(dictionary: [input.key: MLFeatureValue(pixelBuffer: image)])
let stop = Date().addingTimeInterval(8)
var count = 0
while Date() < stop { try autoreleasepool { _ = try model.prediction(from: features) }; count += 1 }
print("Core ML predictions: \(count); computeUnits: cpuAndNeuralEngine")
