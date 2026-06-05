/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Port of customtasks/tinygarden/TinyGardenTools.kt
//
// NOTE: Android used @Tool / @ToolParam / ToolSet annotations from litertlm.
// iOS represents tools as JSON function-spec dictionaries passed to LlmModelHelper.
// The TinyGardenToolSet holds the specs and the dispatch/callback logic.

import Foundation

/// Items used in the Tiny Garden game. Mirrors `TinyGardenItem`.
enum TinyGardenItem: Int, CaseIterable {
    case sunflower = 0
    case daisy
    case rose
    case special
    case wateringCan
    case scythe

    var label: String {
        switch self {
        case .sunflower:   return "sunflower"
        case .daisy:       return "daisy"
        case .rose:        return "rose"
        case .special:     return "secret"
        case .wateringCan: return "water"
        case .scythe:      return "harvest"
        }
    }
}

/// A command sent to the Tiny Garden web game. Mirrors `TinyGardenCommand`.
struct TinyGardenCommand {
    /// 1-based item index matching the game's JS API (`item` field).
    let item: Int
    /// 1-based plot indices.
    let plots: [Int]
    let ts: TimeInterval

    init(item: Int, plots: [Int], ts: TimeInterval = Date().timeIntervalSince1970) {
        self.item = item
        self.plots = plots
        self.ts = ts
    }
}

/// Tool set for the Tiny Garden game. Mirrors `TinyGardenTools`.
final class TinyGardenToolSet {
    let onFunctionCalled: (TinyGardenCommand) -> Void

    init(onFunctionCalled: @escaping (TinyGardenCommand) -> Void) {
        self.onFunctionCalled = onFunctionCalled
    }

    // MARK: - Tool functions

    func waterPlots(plots: [Int]) -> [String: Any] {
        onFunctionCalled(TinyGardenCommand(item: TinyGardenItem.wateringCan.rawValue + 1, plots: plots))
        return ["result": "success", "plots": plots]
    }

    func plantSeed(seed: String, plots: [Int]) -> [String: Any] {
        let itemId: Int
        switch seed.lowercased() {
        case "sunflower": itemId = TinyGardenItem.sunflower.rawValue
        case "daisy":     itemId = TinyGardenItem.daisy.rawValue
        case "rose":      itemId = TinyGardenItem.rose.rawValue
        case "special", "edge gallery", "secret": itemId = TinyGardenItem.special.rawValue
        default:          itemId = -2  // unknown seed; don't fire callback
        }
        if itemId >= 0 {
            onFunctionCalled(TinyGardenCommand(item: itemId + 1, plots: plots))
        }
        return ["result": "success", "seed": seed, "plots": plots]
    }

    func harvestPlots(plots: [Int]) -> [String: Any] {
        onFunctionCalled(TinyGardenCommand(item: TinyGardenItem.scythe.rawValue + 1, plots: plots))
        return ["result": "success", "plots": plots]
    }

    // MARK: - JSON function specs

    static var functionSpecs: [[String: Any]] {
        [
            [
                "name": "waterPlots",
                "description": "Water one or more garden plots.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "plots": [
                            "type": "array",
                            "items": ["type": "integer"],
                            "description": "The IDs of the plots to water.",
                        ],
                    ],
                    "required": ["plots"],
                ],
            ],
            [
                "name": "plantSeed",
                "description": "Plant a seed in one or more garden plots.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "seed": [
                            "type": "string",
                            "description": "The name of the seed to plant.",
                        ],
                        "plots": [
                            "type": "array",
                            "items": ["type": "integer"],
                            "description": "The IDs of the plots to plant a seed in.",
                        ],
                    ],
                    "required": ["seed", "plots"],
                ],
            ],
            [
                "name": "harvestPlots",
                "description": "Harvest one or more garden plots.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "plots": [
                            "type": "array",
                            "items": ["type": "integer"],
                            "description": "The IDs of the plots to harvest.",
                        ],
                    ],
                    "required": ["plots"],
                ],
            ],
        ]
    }

    // MARK: - Dispatch

    func dispatch(functionName: String, args: [String: Any]) -> String {
        var result: [String: Any]
        switch functionName {
        case "waterPlots":
            let plots = args["plots"] as? [Int] ?? []
            result = waterPlots(plots: plots)
        case "plantSeed":
            let seed  = args["seed"]  as? String ?? ""
            let plots = args["plots"] as? [Int] ?? []
            result = plantSeed(seed: seed, plots: plots)
        case "harvestPlots":
            let plots = args["plots"] as? [Int] ?? []
            result = harvestPlots(plots: plots)
        default:
            result = ["result": "unknown_function"]
        }
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
