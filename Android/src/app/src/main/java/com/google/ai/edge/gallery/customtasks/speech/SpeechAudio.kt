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

package com.google.ai.edge.gallery.customtasks.speech

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.util.Log
import com.google.ai.edge.gallery.data.CategoryInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext

private const val TAG = "AGSpeechAudio"

/** The sample rate (Hz) shared by the speech models bundled with the Speech tasks. */
const val SPEECH_SAMPLE_RATE = 16000

/**
 * The home-screen category (tab) that groups the speech-related custom tasks (Text to Speech and
 * Speech to Text).
 */
val SpeechCategory = CategoryInfo(id = "speech", label = "Speech")

/**
 * Plays back PCM audio produced by a TTS model.
 *
 * Samples are expected to be mono floats in the [-1, 1] range, which is exactly what
 * `sherpa-onnx`'s `GeneratedAudio.samples` provides. Playback runs on a background thread so the
 * caller is never blocked.
 */
class AudioPlayer {
  private var track: AudioTrack? = null
  private var writerThread: Thread? = null

  fun play(samples: FloatArray, sampleRate: Int) {
    stop()
    if (samples.isEmpty()) {
      return
    }

    val minBufferSize =
      AudioTrack.getMinBufferSize(
        sampleRate,
        AudioFormat.CHANNEL_OUT_MONO,
        AudioFormat.ENCODING_PCM_FLOAT,
      )
    val bufferSize = if (minBufferSize > 0) minBufferSize else sampleRate * 4

    val newTrack =
      AudioTrack(
        AudioAttributes.Builder()
          .setUsage(AudioAttributes.USAGE_MEDIA)
          .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
          .build(),
        AudioFormat.Builder()
          .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
          .setSampleRate(sampleRate)
          .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
          .build(),
        bufferSize,
        AudioTrack.MODE_STREAM,
        AudioManager.AUDIO_SESSION_ID_GENERATE,
      )
    track = newTrack
    newTrack.play()

    writerThread =
      Thread {
          try {
            var offset = 0
            while (offset < samples.size && !Thread.currentThread().isInterrupted) {
              val written =
                newTrack.write(
                  samples,
                  offset,
                  samples.size - offset,
                  AudioTrack.WRITE_BLOCKING,
                )
              if (written <= 0) {
                break
              }
              offset += written
            }
          } catch (e: Exception) {
            Log.w(TAG, "Audio playback interrupted", e)
          }
        }
        .also { it.start() }
  }

  /**
   * Plays [samples] and suspends until playback finishes (or the calling coroutine is cancelled).
   *
   * Unlike [play] (fire-and-forget), this is meant for **sequential streaming playback**: a caller
   * can `playToCompletion(sentence1); playToCompletion(sentence2); …` and each clip plays fully
   * before the next begins. Cancelling the coroutine (e.g. on barge-in) stops playback promptly.
   */
  suspend fun playToCompletion(samples: FloatArray, sampleRate: Int) {
    stop()
    if (samples.isEmpty()) {
      return
    }
    withContext(Dispatchers.IO) {
      val minBufferSize =
        AudioTrack.getMinBufferSize(
          sampleRate,
          AudioFormat.CHANNEL_OUT_MONO,
          AudioFormat.ENCODING_PCM_FLOAT,
        )
      val bufferSize = if (minBufferSize > 0) minBufferSize else sampleRate * 4
      val t =
        AudioTrack(
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build(),
          AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
            .setSampleRate(sampleRate)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build(),
          bufferSize,
          AudioTrack.MODE_STREAM,
          AudioManager.AUDIO_SESSION_ID_GENERATE,
        )
      track = t
      try {
        t.play()
        var offset = 0
        while (offset < samples.size && isActive) {
          val written =
            t.write(samples, offset, samples.size - offset, AudioTrack.WRITE_BLOCKING)
          if (written <= 0) {
            break
          }
          offset += written
        }
        // The last write returns once the data is buffered; wait until the playback head has
        // actually reached the end so the clip isn't cut off before the next one starts.
        while (isActive && t.playbackHeadPosition < samples.size) {
          delay(20)
        }
      } catch (e: Exception) {
        Log.w(TAG, "Sequential audio playback interrupted", e)
      } finally {
        try {
          t.pause()
          t.flush()
          t.stop()
        } catch (e: Exception) {
          Log.w(TAG, "Failed to stop AudioTrack", e)
        }
        t.release()
        if (track === t) {
          track = null
        }
      }
    }
  }

  fun stop() {
    writerThread?.interrupt()
    writerThread = null
    track?.let { t ->
      try {
        t.pause()
        t.flush()
        t.stop()
      } catch (e: Exception) {
        Log.w(TAG, "Failed to stop AudioTrack", e)
      }
      t.release()
    }
    track = null
  }
}

/**
 * Records microphone audio as mono float samples in the [-1, 1] range, ready to be fed directly
 * into a `sherpa-onnx` recognizer.
 *
 * The caller is responsible for holding the `RECORD_AUDIO` runtime permission before calling
 * [start].
 */
class AudioRecorder(private val sampleRate: Int = SPEECH_SAMPLE_RATE) {
  @Volatile private var recording = false
  private var recordThread: Thread? = null
  private val chunks = mutableListOf<FloatArray>()

  @SuppressLint("MissingPermission")
  fun start() {
    if (recording) {
      return
    }
    synchronized(chunks) { chunks.clear() }

    val minBufferSize =
      AudioRecord.getMinBufferSize(
        sampleRate,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT,
      )
    val bufferSize = if (minBufferSize > 0) minBufferSize * 2 else sampleRate * 2

    val recorder =
      AudioRecord(
        MediaRecorder.AudioSource.VOICE_RECOGNITION,
        sampleRate,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT,
        bufferSize,
      )
    if (recorder.state != AudioRecord.STATE_INITIALIZED) {
      recorder.release()
      throw IllegalStateException("Failed to initialize AudioRecord")
    }

    recording = true
    recorder.startRecording()
    recordThread =
      Thread {
          val buffer = ShortArray(bufferSize / 2)
          try {
            while (recording) {
              val read = recorder.read(buffer, 0, buffer.size)
              if (read > 0) {
                val floats = FloatArray(read) { buffer[it] / 32768.0f }
                synchronized(chunks) { chunks.add(floats) }
              }
            }
          } finally {
            try {
              recorder.stop()
            } catch (e: Exception) {
              Log.w(TAG, "Failed to stop AudioRecord", e)
            }
            recorder.release()
          }
        }
        .also { it.start() }
  }

  /** Stops recording and returns all captured samples concatenated into a single array. */
  fun stop(): FloatArray {
    if (!recording) {
      return FloatArray(0)
    }
    recording = false
    recordThread?.join(2000)
    recordThread = null

    synchronized(chunks) {
      val total = chunks.sumOf { it.size }
      val out = FloatArray(total)
      var offset = 0
      for (chunk in chunks) {
        chunk.copyInto(out, offset)
        offset += chunk.size
      }
      chunks.clear()
      return out
    }
  }

  fun isRecording(): Boolean = recording
}
