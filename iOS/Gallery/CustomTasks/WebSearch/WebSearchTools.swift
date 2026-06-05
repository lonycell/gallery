// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License"); see LICENSE.
// Port of customtasks/websearch/WebSearchTools.kt

import Foundation

// MARK: - WebSearchTools

/// A built-in tool that lets the agent search the internet via DuckDuckGo (key-free).
/// Mirrors `WebSearchTools : ToolSet` from Android.
///
/// NOTE: No LiteRT-LM `@Tool` annotation equivalent on iOS. Expose this as a `ToolProvider`
/// when wiring into the inference runtime.
final class WebSearchTools {
    private weak var agentTools: AgentTools?

    init(agentTools: AgentTools? = nil) {
        self.agentTools = agentTools
    }

    /// Searches the public internet and returns the top results as text.
    /// Mirrors `@Tool fun searchWeb(query)`.
    func searchWeb(query: String) async -> [String: String] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return ["status": "failed", "error": "empty query"]
        }
        await agentTools?.postProgress(label: "인터넷 검색 중…", inProgress: true)
        do {
            let results = try await WebSearch.search(query: query)
            await agentTools?.postProgress(label: "", inProgress: false)
            if results.isEmpty {
                return ["status": "empty", "note": "No relevant results were found."]
            }
            return ["status": "ok", "query": query, "results": results]
        } catch {
            await agentTools?.postProgress(label: "", inProgress: false)
            return ["status": "failed", "error": error.localizedDescription]
        }
    }
}

// MARK: - WebSearch engine

/// Key-free web search. Primary source: DuckDuckGo HTML "lite". Fallback: Wikipedia API.
/// Mirrors `object WebSearch` from Android.
enum WebSearch {
    private static let MAX_RESULTS = 6
    private static let UA = "Mozilla/5.0 (iOS) BeF-Ai/1.0"

    static func search(query: String) async throws -> String {
        if let duck = try? await searchDuckDuckGoHtml(query: query), !duck.isEmpty { return duck }
        return (try? await searchWikipedia(query: query)) ?? ""
    }

    // MARK: - DuckDuckGo HTML

    private static func searchDuckDuckGoHtml(query: String) async throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://lite.duckduckgo.com/lite/?q=\(encoded)") else { return "" }
        var req = URLRequest(url: url)
        req.setValue(UA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        req.setValue("ko,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return "" }
        let html = String(data: data, encoding: .utf8) ?? ""

        let linkPat = try! NSRegularExpression(pattern: #"<a[^>]*class="result-link"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators])
        let snippetPat = try! NSRegularExpression(pattern: #"<td[^>]*class="result-snippet"[^>]*>(.*?)</td>"#, options: [.dotMatchesLineSeparators])
        let ns = html as NSString

        let titles = linkPat.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { cleanHtml(ns.substring(with: $0.range(at: 1))) }
        let snippets = snippetPat.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { cleanHtml(ns.substring(with: $0.range(at: 1))) }

        var result = [String]()
        for i in 0..<min(titles.count, MAX_RESULTS) {
            let t = titles[i]; let s = snippets.indices.contains(i) ? snippets[i] : ""
            if !t.isEmpty || !s.isEmpty { result.append("- \(t)\(s.isEmpty ? "" : ": \(s)")") }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Wikipedia fallback

    private static func searchWikipedia(query: String) async throws -> String {
        let lang = containsHangul(query) ? "ko" : "en"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&srlimit=\(MAX_RESULTS)&format=json&utf8=1") else { return "" }
        var req = URLRequest(url: url)
        req.setValue(UA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let search = query["search"] as? [[String: Any]] else { return "" }
        var result = [String]()
        for item in search.prefix(MAX_RESULTS) {
            let title = (item["title"] as? String) ?? ""
            let snippet = cleanHtml((item["snippet"] as? String) ?? "")
            if !title.isEmpty { result.append("- \(title)\(snippet.isEmpty ? "" : ": \(snippet)")") }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func cleanHtml(_ raw: String) -> String {
        var s = raw
        let tagPat = try! NSRegularExpression(pattern: "<[^>]+>")
        s = tagPat.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let spacePat = try! NSRegularExpression(pattern: "\\s+")
        s = spacePat.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { ($0.value >= 0xAC00 && $0.value <= 0xD7A3) || ($0.value >= 0x1100 && $0.value <= 0x11FF) || ($0.value >= 0x3130 && $0.value <= 0x318F) }
    }
}
