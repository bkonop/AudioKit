//: ## Noise Operations
//:

import AudioKit

let generator = OperationGenerator {
    let white = AKOperation.whiteNoise()
    let pink = AKOperation.pinkNoise()

    let lfo = AKOperation.sineWave(frequency: 0.3)
    let balance = lfo.scale(minimum: 0, maximum: 1)
    let noise = mixer(white, pink, balance: balance)
    return noise.pan(lfo)
}

engine.output = generator
try engine.start()

generator.start()

import PlaygroundSupport
PlaygroundPage.current.needsIndefiniteExecution = true
