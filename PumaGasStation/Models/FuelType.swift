//
//  FuelType.swift
//  PumaGasStation
//

import Foundation

enum FuelType: String, CaseIterable, Identifiable, Codable {
    case súper = "Súper"
    case regular = "Regular"
    case diésel = "Diésel"

    var id: String { rawValue }

}
