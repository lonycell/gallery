/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of proto/skill.proto -> Codable Swift structs.

import Foundation

struct Skill: Codable, Identifiable {
  var name: String = ""
  var description: String = ""
  var instructions: String = ""
  var builtIn: Bool = false
  var skillUrl: String = ""
  var importDirName: String = ""
  var selected: Bool = false
  var requireSecret: Bool = false
  var requireSecretDescription: String = ""
  var homepage: String = ""
  var userModifiedSelection: Bool = false
  var id: String { name }
}

struct Skills: Codable {
  var skill: [Skill] = []
  static let defaultInstance = Skills()
}
