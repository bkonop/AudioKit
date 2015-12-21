//
//  highPassFilter.swift
//  AudioKit For iOS
//
//  Autogenerated by scripts by Aurelius Prochazka. Do not edit directly.
//  Copyright © 2015 AudioKit. All rights reserved.
//

import Foundation

extension AKOperation {

    /** highPassFilter: A first-order recursive high-pass filter with variable frequency response. - A complement to the AKLowPassFilter.

     - parameter halfPowerPoint: Half-Power Pointin Hertz. Half power is defined as peak power / root 2. (Default: 1000, Minimum: 12, Maximum: 20000)
     */
    public mutating func highPassFilter(halfPowerPoint halfPowerPoint: AKParameter = 1000) {
        self = self.highPassFiltered(halfPowerPoint: halfPowerPoint)
    }

    /** highPassFiltered: A first-order recursive high-pass filter with variable frequency response. - A complement to the AKLowPassFilter.

     - returns: AKOperation
     - parameter halfPowerPoint: Half-Power Pointin Hertz. Half power is defined as peak power / root 2. (Default: 1000, Minimum: 12, Maximum: 20000)
     */
    public func highPassFiltered(halfPowerPoint halfPowerPoint: AKParameter = 1000) -> AKOperation {
        return AKOperation("\(self) \(halfPowerPoint) atone ")
    }
}
