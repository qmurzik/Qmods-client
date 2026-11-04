import type { McpServer } from "@modelcontextprotocol/server";
import { z } from "zod";
import { addTool, httpError, humanSize } from "../util";

const API = "https://cloud-api.yandex.net/v1/disk/public/resources";
const SVC = "Яндекс Диск (публичная ссылка)";

const keyArg = z
  .string()
  .min(3)
  .describe("Публичная ссылка (https://disk.yandex.ru/d/..., https://yadi.sk/d/..., https://disk.yandex.ru/i/...) или public_key");

const subPath = z.string().optional().describe('Путь внутри опубликованной папки, например "/sub/file.txt"');

async function get(path: string, params: Record<string, string | number | undefined>): Promise<any> {
  const u = new URL(API + path);
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") u.searchParams.set(k, String(v));
  const res = await fetch(u, { headers: { Accept: "application/json" } });
  if (!res.ok) throw await httpError(SVC, res);
  return res.json();
}

function slim(r: any) {
  return {
    name: r.name,
    path: r.path,
    type: r.type,
    size: r.size,
    size_human: humanSize(r.size),
    mime_type: r.mime_type,
    modified: r.modified,
    md5: r.md5,
  };
}

/** Always registered — needs no token. */
export function registerYandexPublic(server: McpServer): void {
  addTool(server, "yadisk_public_info", `${SVC}: метаданные по публичной ссылке без токена; для папки — список содержимого с пагинацией.`, z.object({
    public_key: keyArg,
    path: subPath,
    limit: z.number().int().min(1).max(1000).default(100),
    offset: z.number().int().min(0).default(0),
  }), async ({ public_key, path, limit, offset }) => {
    const r = await get("", { public_key: public_key.trim(), path, limit, offset });
    const out: any = { ...slim(r), public_url: r.public_url, owner: r.owner?.display_name, views_count: r.views_count };
    if (r.type === "dir") {
      const e = r._embedded ?? {};
      out.total = e.total;
      out.offset = e.offset;
      out.items = (e.items ?? []).map(slim);
    }
    return out;
  }, { readOnlyHint: true });

  addTool(server, "yadisk_public_download_link", `${SVC}: прямая ссылка на скачивание по публичной ссылке без токена (папка — zip-архивом). Можно указать файл внутри опубликованной папки.`, z.object({
    public_key: keyArg,
    path: subPath,
  }), async ({ public_key, path }) => {
    const r = await get("/download", { public_key: public_key.trim(), path });
    return { href: r.href, method: r.method ?? "GET" };
  }, { readOnlyHint: true });
}
