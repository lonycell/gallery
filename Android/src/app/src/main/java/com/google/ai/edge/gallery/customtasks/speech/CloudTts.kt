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

import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.inject.Inject
import javax.inject.Singleton
import org.json.JSONObject

private const val TAG = "AGCloudTts"

/** Decoded audio ready for [AudioPlayer]. */
data class CloudAudio(val samples: FloatArray, val sampleRate: Int)

/** A selectable speaker (voice) within a cloud provider. */
data class CloudTtsVoice(val speakerId: String, val label: String)

/**
 * A commercial TTS provider configured by parameters (not a downloaded model): a base URL, an API
 * token (+ optional client id / user info) and the list of available speaker ids.
 */
data class CloudTtsProvider(
  val id: String,
  val name: String,
  val baseUrl: String,
  val apiToken: String,
  /** Extra credential when the provider needs two (e.g. Naver client id). Empty otherwise. */
  val clientId: String = "",
  val voices: List<CloudTtsVoice>,
)

const val CLOUD_PROVIDER_ELEVENLABS = "elevenlabs"
const val CLOUD_PROVIDER_CLOVA = "clova"
private const val VOICE_ID_PREFIX = "cloud"

/**
 * Cloud (commercial) TTS support — ElevenLabs and Naver Clova for now.
 *
 * Unlike the on-device neural voices, these are not downloaded; they are called over HTTP using the
 * configured parameters. The auth tokens / client ids below are SAMPLE placeholders — replace them
 * (eventually via a settings screen) with real credentials to enable the providers.
 *
 * Voices are surfaced to the rest of the app as voice ids of the form
 * `cloud:<providerId>:<speakerId>` so a character can be assigned a cloud speaker through the same
 * per-character voice selection used for the on-device voices.
 */
@Singleton
class CloudTtsService @Inject constructor() {

  // Mutable so a future settings UI can update credentials / speakers at runtime.
  @Volatile
  var providers: List<CloudTtsProvider> = defaultSampleProviders()
    private set

  fun setProviders(newProviders: List<CloudTtsProvider>) {
    providers = newProviders
  }

  /** Returns the selectable cloud voices as (voiceId, label) pairs for the voice picker. */
  fun voiceOptions(): List<Pair<String, String>> =
    providers.flatMap { provider ->
      provider.voices.map { voice ->
        "$VOICE_ID_PREFIX:${provider.id}:${voice.speakerId}" to "${provider.name} · ${voice.label}"
      }
    }

  fun isCloudVoice(voiceId: String): Boolean = voiceId.startsWith("$VOICE_ID_PREFIX:")

  /**
   * Synthesizes [text] for the cloud voice [voiceId] (`cloud:<provider>:<speaker>`), blocking on the
   * network. Returns null on any failure (caller should fall back / surface an error). Call off the
   * main thread.
   */
  fun synthesize(voiceId: String, text: String): CloudAudio? {
    val parts = voiceId.split(":", limit = 3)
    if (parts.size != 3 || parts[0] != VOICE_ID_PREFIX) return null
    val provider = providers.firstOrNull { it.id == parts[1] } ?: return null
    val speaker = parts[2]
    return try {
      when (provider.id) {
        CLOUD_PROVIDER_ELEVENLABS -> synthesizeElevenLabs(provider, speaker, text)
        CLOUD_PROVIDER_CLOVA -> synthesizeClova(provider, speaker, text)
        else -> null
      }
    } catch (e: Exception) {
      Log.w(TAG, "Cloud TTS synthesis failed for '$voiceId'", e)
      null
    }
  }

  /** ElevenLabs: POST text, request raw PCM (16-bit, 22.05 kHz, mono). */
  private fun synthesizeElevenLabs(
    provider: CloudTtsProvider,
    speaker: String,
    text: String,
  ): CloudAudio? {
    val url = URL("${provider.baseUrl}/v1/text-to-speech/$speaker?output_format=pcm_22050")
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "POST"
      connectTimeout = 15_000
      readTimeout = 30_000
      doOutput = true
      setRequestProperty("xi-api-key", provider.apiToken)
      setRequestProperty("Content-Type", "application/json")
      setRequestProperty("Accept", "audio/pcm")
    }
    val body =
      JSONObject()
        .put("text", text)
        .put("model_id", "eleven_multilingual_v2")
        .toString()
    conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
    return readPcm(conn, sampleRate = 22050)
  }

  /** Naver Clova Voice (Premium): form POST, request WAV (PCM16) which we decode. */
  private fun synthesizeClova(
    provider: CloudTtsProvider,
    speaker: String,
    text: String,
  ): CloudAudio? {
    val url = URL("${provider.baseUrl}/tts-premium/v1/tts")
    val conn = (url.openConnection() as HttpURLConnection).apply {
      requestMethod = "POST"
      connectTimeout = 15_000
      readTimeout = 30_000
      doOutput = true
      setRequestProperty("X-NCP-APIGW-API-KEY-ID", provider.clientId)
      setRequestProperty("X-NCP-APIGW-API-KEY", provider.apiToken)
      setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
    }
    fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
    val form = "speaker=${enc(speaker)}&format=wav&sampleRate=24000&text=${enc(text)}"
    conn.outputStream.use { it.write(form.toByteArray(Charsets.UTF_8)) }
    val code = conn.responseCode
    if (code != HttpURLConnection.HTTP_OK) {
      Log.w(TAG, "Clova TTS HTTP $code: ${errorText(conn)}")
      return null
    }
    val wav = conn.inputStream.use { it.readBytes() }
    return parseWav(wav)
  }

  private fun readPcm(conn: HttpURLConnection, sampleRate: Int): CloudAudio? {
    val code = conn.responseCode
    if (code != HttpURLConnection.HTTP_OK) {
      Log.w(TAG, "Cloud TTS HTTP $code: ${errorText(conn)}")
      return null
    }
    val bytes = conn.inputStream.use { it.readBytes() }
    if (bytes.isEmpty()) return null
    return CloudAudio(pcm16leToFloat(bytes), sampleRate)
  }

  private fun errorText(conn: HttpURLConnection): String =
    try {
      conn.errorStream?.use { String(it.readBytes(), Charsets.UTF_8) }?.take(300) ?: ""
    } catch (e: Exception) {
      ""
    }

  private fun pcm16leToFloat(bytes: ByteArray): FloatArray {
    val count = bytes.size / 2
    val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
    return FloatArray(count) { bb.short / 32768.0f }
  }

  /** Minimal WAV (PCM16) parser: finds the `fmt ` sample rate and the `data` chunk. */
  private fun parseWav(bytes: ByteArray): CloudAudio? {
    if (bytes.size < 44) return null
    var pos = 12 // skip "RIFF"<size>"WAVE"
    var sampleRate = 24000
    var dataOffset = -1
    var dataLen = 0
    while (pos + 8 <= bytes.size) {
      val id = String(bytes, pos, 4, Charsets.US_ASCII)
      val size = ByteBuffer.wrap(bytes, pos + 4, 4).order(ByteOrder.LITTLE_ENDIAN).int
      val body = pos + 8
      when (id) {
        "fmt " -> if (body + 8 <= bytes.size) {
          sampleRate = ByteBuffer.wrap(bytes, body + 4, 4).order(ByteOrder.LITTLE_ENDIAN).int
        }
        "data" -> {
          dataOffset = body
          dataLen = size
        }
      }
      pos = body + size + (size and 1) // chunks are word-aligned
    }
    if (dataOffset < 0) return null
    val end = minOf(dataOffset + dataLen, bytes.size)
    if (end <= dataOffset) return null
    return CloudAudio(pcm16leToFloat(bytes.copyOfRange(dataOffset, end)), sampleRate)
  }

  private fun defaultSampleProviders(): List<CloudTtsProvider> =
    listOf(
      CloudTtsProvider(
        id = CLOUD_PROVIDER_ELEVENLABS,
        name = "ElevenLabs",
        baseUrl = "https://api.elevenlabs.io",
        // SAMPLE — replace with a real ElevenLabs API key.
        apiToken = "sk_SAMPLE_ELEVENLABS_API_KEY",
        voices =
          listOf(
            CloudTtsVoice("21m00Tcm4TlvDq8ikWAM", "Rachel"),
            CloudTtsVoice("AZnzlk1XvdvUeBnXmlld", "Domi"),
            CloudTtsVoice("EXAVITQu4vr4xnSDxMaL", "Sarah"),
            CloudTtsVoice("TxGEqnHWrfWFTfGW9XjX", "Josh"),
          ),
      ),
      CloudTtsProvider(
        id = CLOUD_PROVIDER_CLOVA,
        name = "Clova",
        baseUrl = "https://naveropenapi.apigw.ntruss.com",
        // SAMPLE — replace with real Naver Cloud Platform credentials.
        apiToken = "SAMPLE_CLOVA_CLIENT_SECRET",
        clientId = "SAMPLE_CLOVA_CLIENT_ID",
        voices =
          listOf(
            CloudTtsVoice("nara", "나라 (여)"),
            CloudTtsVoice("nminyoung", "민영 (여)"),
            CloudTtsVoice("nyejin", "예진 (여)"),
            CloudTtsVoice("jinho", "진호 (남)"),
          ),
      ),
    )
}
