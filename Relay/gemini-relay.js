/**
 * UniChat — релей для Gemini API.
 *
 * Зачем: домен generativelanguage.googleapis.com может быть недоступен в РФ.
 * Этот Worker проксирует только запросы к Gemini и не хранит ключи и ответы.
 *
 * Развёртывание (бесплатный план Cloudflare):
 *   1. https://dash.cloudflare.com → Workers & Pages → Create Worker
 *   2. Вставьте этот файл, нажмите Deploy.
 *   3. Скопируйте адрес вида https://имя.workers.dev
 *   4. В UniChat: Настройки → Gemini → Base URL = этот адрес.
 *
 * Необязательная защита:
 *   Добавьте переменную окружения RELAY_SECRET (Settings → Variables).
 *   Тогда в настройках провайдера в «Доп. заголовки» добавьте строку:
 *       x-relay-secret: ВАШ_СЕКРЕТ
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (!url.pathname.startsWith("/v1beta/") && !url.pathname.startsWith("/v1/")) {
      return new Response("UniChat Gemini relay. Use /v1beta/... paths.\n", {
        status: 200,
        headers: { "content-type": "text/plain; charset=utf-8" }
      });
    }

    if (env && env.RELAY_SECRET) {
      const provided = request.headers.get("x-relay-secret");
      if (provided !== env.RELAY_SECRET) {
        return new Response("Forbidden", { status: 403, headers: corsHeaders() });
      }
    }

    const target = "https://generativelanguage.googleapis.com" + url.pathname + url.search;

    const headers = new Headers(request.headers);
    headers.delete("host");
    headers.delete("cf-connecting-ip");
    headers.delete("x-relay-secret");

    const init = {
      method: request.method,
      headers,
      body: request.method === "GET" || request.method === "HEAD" ? undefined : request.body,
      redirect: "follow"
    };

    try {
      const response = await fetch(target, init);
      const resultHeaders = new Headers(response.headers);
      for (const [key, value] of Object.entries(corsHeaders())) {
        resultHeaders.set(key, value);
      }
      return new Response(response.body, {
        status: response.status,
        headers: resultHeaders
      });
    } catch (error) {
      return new Response("Relay error: " + (error && error.message ? error.message : "unknown"), {
        status: 502,
        headers: corsHeaders()
      });
    }
  }
};

function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type,x-goog-api-key,x-relay-secret,authorization"
  };
}
