/*
 * Dash Chat bridge helper.
 *
 * Wraps the native `window.AiEdgeLlm` interface (injected by the app) into a small Promise/streaming
 * API the pages use. The native side streams via window.aiEdgeLlmOnToken / onDone / onError.
 *
 * Usage:
 *   DashChat.isReady()                         -> boolean
 *   DashChat.chat(prompt, onToken)             -> Promise<fullText>   (onToken(delta, soFar))
 *   DashChat.cancel()                          -> cancels in-flight requests
 */
(function () {
  var pending = {};
  var seq = 0;

  window.aiEdgeLlmOnToken = function (id, delta) {
    var p = pending[id];
    if (p) {
      p.text += delta;
      if (p.onToken) p.onToken(delta, p.text);
    }
  };
  window.aiEdgeLlmOnDone = function (id, full) {
    var p = pending[id];
    if (p) {
      delete pending[id];
      p.resolve(full || p.text);
    }
  };
  window.aiEdgeLlmOnError = function (id, message) {
    var p = pending[id];
    if (p) {
      delete pending[id];
      p.reject(new Error(message || 'unknown error'));
    }
  };

  window.DashChat = {
    isReady: function () {
      try {
        return !!(window.AiEdgeLlm && window.AiEdgeLlm.isReady());
      } catch (e) {
        return false;
      }
    },
    chat: function (prompt, onToken) {
      return new Promise(function (resolve, reject) {
        if (!window.AiEdgeLlm) {
          reject(new Error('LLM 브리지를 찾을 수 없어요. 앱의 대쉬 챗에서 열어주세요.'));
          return;
        }
        var id = 'req-' + ++seq + '-' + Date.now();
        pending[id] = { text: '', onToken: onToken, resolve: resolve, reject: reject };
        try {
          window.AiEdgeLlm.sendPrompt(id, prompt);
        } catch (e) {
          delete pending[id];
          reject(e);
        }
      });
    },
    cancel: function () {
      try {
        for (var id in pending) {
          if (window.AiEdgeLlm) window.AiEdgeLlm.cancel(id);
          delete pending[id];
        }
      } catch (e) {}
    },
  };
})();
