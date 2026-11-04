import type { McpServer } from "@modelcontextprotocol/server";
import { z } from "zod";
import { addTool, httpError, humanSize, UserError } from "../util";

const SVC = "Облако Mail.ru (публичная ссылка, неофициальный API)";

/** "https://cloud.mail.ru/public/AbC/xYz/sub/file.txt" -> "AbC/xYz/sub/file.txt" */
export function parseWeblink(input: string): string {
  const s = input.trim();
  const m = s.match(/cloud\.mail\.ru\/public\/(.+)$/i);
  let w = m ? m[1] : s;
  w = w.split(/[?#]/)[0].replace(/^\/+|\/+$/g, "");
  try {
    w = decodeURIComponent(w);
  } catch {
    /* keep as is */
  }
  if (!/^[^/]+\/[^/]+/.test(w)) throw new UserError("Не похоже на публичную ссылку вида https://cloud.mail.ru/public/XXXX/YYYY");
  return w;
}

function encWeblink(w: string): string {
  return w.split("/").map(encodeURIComponent).join("/");
}

async function weblinkGetBase(): Promise<string> {
  const res = await fetch("https://cloud.mail.ru/api/v2/dispatcher", { headers: { Accept: "application/json" } });
  if (!res.ok) throw await httpError(SVC + " (dispatcher)", res);
  const j: any = await res.json();
  const url = j?.body?.weblink_get?.[0]?.url;
  if (!url) throw new UserError("Диспетчер Mail.ru не вернул сервер для скачивания");
  return String(url).replace(/\/+$/, "");
}

function slim(it: any, base?: string) {
  const out: any = {
    name: it.name,
    type: it.type,
    weblink: it.weblink,
    size: it.size,
    size_human: humanSize(it.size),
  };
  if (it.mtime) out.modified = new Date(it.mtime * 1000).toISOString();
  if (it.hash) out.hash = it.hash;
  if (base && it.type === "file" && it.weblink) out.download_url = `${base}/${encWeblink(it.weblink)}`;
  return out;
}

/** Always registered — needs no credentials. */
export function registerMailruPublic(server: McpServer): void {
  addTool(server, "mailru_public_list", `${SVC}: содержимое публичной папки/информация о файле по ссылке cloud.mail.ru/public/... без авторизации. Для файлов сразу отдаются прямые ссылки на скачивание.`, z.object({
    url: z.string().describe("Публичная ссылка https://cloud.mail.ru/public/XXXX/YYYY (можно с подпутём) или weblink XXXX/YYYY"),
    limit: z.number().int().min(1).max(500).default(100),
    offset: z.number().int().min(0).default(0),
  }), async ({ url, limit, offset }) => {
    const weblink = parseWeblink(url);
    const u = new URL("https://cloud.mail.ru/api/v2/folder");
    u.searchParams.set("weblink", weblink);
    u.searchParams.set("offset", String(offset));
    u.searchParams.set("limit", String(limit));
    const res = await fetch(u, { headers: { Accept: "application/json" } });
    if (!res.ok) {
      if (res.status === 404) throw new UserError("Публичная ссылка не найдена или закрыта");
      throw await httpError(SVC, res);
    }
    const j: any = await res.json();
    const b = j.body ?? {};
    const base = await weblinkGetBase().catch(() => undefined);
    if (b.type !== "folder" && !b.list) return slim(b, base);
    return {
      name: b.name,
      weblink: b.weblink ?? weblink,
      count: b.count,
      offset,
      items: (b.list ?? []).map((it: any) => slim(it, base)),
    };
  }, { readOnlyHint: true });

  addTool(server, "mailru_public_download_link", `${SVC}: прямая ссылка на скачивание файла по публичной ссылке (для файла внутри опубликованной папки добавьте подпуть к ссылке).`, z.object({
    url: z.string().describe("https://cloud.mail.ru/public/XXXX/YYYY[/путь/к/файлу]"),
  }), async ({ url }) => {
    const weblink = parseWeblink(url);
    const base = await weblinkGetBase();
    return { href: `${base}/${encWeblink(weblink)}`, note: "Ссылка привязана к серверу-диспетчеру и может устареть через несколько часов — при ошибке запросите заново." };
  }, { readOnlyHint: true });
}
