/*
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of data/SkillAllowlist.kt

import Foundation

/// A skill in the featured skill allowlist. Mirrors `AllowedSkill`.
struct AllowedSkill: Codable {
  let name: String
  let description: String
  let skillUrl: String
  var attributionLabel: String? = nil
  var attributionUrl: String? = nil
}

/// The featured skill allowlist. Mirrors `SkillAllowlist`.
struct SkillAllowlist: Codable {
  let featuredSkills: [AllowedSkill]
}
