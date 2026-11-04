import { McpServer } from "@modelcontextprotocol/server";
import { createMcpHandler } from "agents/mcp/server";
import type { Env } from "./env";
import { registerMailru } from "./services/mailru";
import { registerMailruPublic } from "./services/mailruPublic";
import { registerS3 } from "./services/s3";
import { registerYandexDisk } from "./services/yandexDisk";
import { registerYandexPublic } from "./services/yandexPublic";

const VERSION = "1.0.0";

function buildServer(env: Env): McpServer {
  const server = new McpServer(
    { name: "ru-files-mcp", version: VERSION },
    {
      instructions:
        "Инструменты для российских файловых хранилищ: Яндекс Диск (yadisk_*), Облако Mail.ru (mailru_*, неофициальный API), " +
        "S3-совместимые хранилища (s3_*). Большие файлы не передаются через сервер: используйте прямые ссылки " +
        "(*_download_link, s3_presigned_url) и загрузку по URL (yadisk_upload_from_url). Текстовые чтение/запись ограничены 1 МБ.",
    },
  );
  // Each module registers its tools only when its secrets are configured.
  registerYandexDisk(server, env);
  registerYandexPublic(server);
  registerMailru(server, env);
  registerMailruPublic(server);
  registerS3(server, env);
  return server;
}

/** Constant-time string comparison. */
function safeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) diff |= (ea[i % (ea.length || 1)] ?? 0) ^ (eb[i % (eb.length || 1)] ?? 0);
  return diff === 0;
}

const notFound = () => new Response("Not found", { status: 404 });

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    // Expected path: /<ACCESS_KEY>/mcp
    const m = url.pathname.match(/^\/([^/]+)\/mcp\/?$/);
    const key = env.ACCESS_KEY;
    if (!m || !key || key.length < 16 || !safeEqual(decodeURIComponent(m[1]), key)) return notFound();

    // Hand the request to the MCP handler on its canonical /mcp route.
    url.pathname = "/mcp";
    const inner = new Request(url.toString(), request);
    const handler = createMcpHandler(() => buildServer(env), { route: "/mcp" });
    return handler(inner, env, ctx);
  },
} satisfies ExportedHandler<Env>;
