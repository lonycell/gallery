/*
 * Copyright 2025 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
 */

// Port of ui/common/chat/MessageBodyAudioClip.kt

import SwiftUI

struct MessageBodyAudioClip: View {
  let message: ChatMessageAudioClip

  var body: some View {
    AudioPlaybackPanel(
      audioData: message.audioData,
      sampleRate: message.sampleRate,
      isRecording: false,
      onDarkBg: true
    )
    .padding(.trailing, 16)
  }
}
