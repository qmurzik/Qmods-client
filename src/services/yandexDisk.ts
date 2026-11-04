import type { McpServer } from "@modelcontextprotocol/server";
import { z } from "zod";
import type { Env } from "../env";
import { addTool, httpError, humanSize, readTextLimited, TEXT_LIMIT, textBytes, UserError } from "../util";

const API = "https://cloud-api.yandex.net/v1/disk";
const SVC = "Яндекс Диск";

type Q = Record<string, string | number | boolean | undefined>;

function qs(params: Q): string {
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") u.set(k, String(v));
  const s = u.toString();
  return s ? `?${s}` : "";
}

/** Normalises user paths: "" / "/" -> "disk:/", "foo" -> "disk:/foo". Leaves disk:/, app:/, trash:/ alone. */
function diskPath(p?: string): string {
  if (!p || p === "/" || p === "disk:" || p === "disk:/") return "disk:/";
  if (/^(disk|app|trash):/.test(p)) return p;
  return "disk:/" + p.replace(/^\/+/, "");
}

/** Short view of a Resource object. */
function slim(r: any): any {
  if (!r || typeof r !== "object") return r;
  const out: any = {
    name: r.name,
    path: r.path,
    type: r.type,
  };
  if (r.size !== undefined) {
    out.size = r.size;
    out.size_human = humanSize(r.size);
  }
  for (const k of ["mime_type", "media_type", "created", "modified", "md5", "public_url", "origin_path", "deleted"]) {
    if (r[k] !== undefined) out[k] = r[k];
  }
  return out;
}

export function registerYandexDisk(server: McpServer, env: Env): void {
  const token = env.YANDEX_DISK_TOKEN;
  if (!token) return;

  async function call(method: string, path: string, params: Q = {}, okStatuses: number[] = []): Promise<any> {
    const res = await fetch(API + path + qs(params), {
      method,
      headers: { Authorization: `OAuth ${token}`, Accept: "application/json" },
    });
    if (!res.ok && !okStatuses.includes(res.status)) throw await httpError(SVC, res);
    if (res.status === 204) return {};
    const text = await res.text();
    return text ? JSON.parse(text) : {};
  }

  /** Follows an async-operation Link (201/202 responses). */
  function opInfo(r: any): any {
    if (r && r.href && /\/operations\//.test(r.href)) {
      const id = r.href.split("/operations/")[1];
      return { status: "in-progress", operation_id: id, hint: "Проверьте статус через yadisk_operation_status" };
    }
    return undefined;
  }

  const pathArg = z.string().describe('Путь на Диске, например "/Документы/отчёт.docx" или "disk:/Фото". Корень — "/"');

  addTool(server, "yadisk_disk_info", `${SVC}: информация о диске — общий/занятый объём, корзина, пользователь.`, z.object({}), async () => {
    const d = await call("GET", "");
    return {
      user: d.user?.display_name ?? d.user?.login,
      total_space: humanSize(d.total_space),
      used_space: humanSize(d.used_space),
      trash_size: humanSize(d.trash_size),
      free_space: humanSize(d.total_space - d.used_space),
      is_paid: d.is_paid,
      system_folders: d.system_folders,
    };
  }, { readOnlyHint: true });

  addTool(server, "yadisk_list", `${SVC}: содержимое папки (с пагинацией: limit/offset).`, z.object({
    path: pathArg.default("/"),
    limit: z.number().int().min(1).max(1000).default(100),
    offset: z.number().int().min(0).default(0),
    sort: z.enum(["name", "path", "created", "modified", "size", "-name", "-path", "-created", "-modified", "-size"]).optional(),
  }), async ({ path, limit, offset, sort }) => {
    const r = await call("GET", "/resources", { path: diskPath(path), limit, offset, sort });
    if (r.type !== "dir") return { item: slim(r), note: "Это файл, а не папка" };
    const e = r._embedded ?? {};
    return {
      path: r.path,
      total: e.total,
      offset: e.offset,
      limit: e.limit,
      has_more: (e.offset ?? 0) + (e.items?.length ?? 0) < (e.total ?? 0),
      items: (e.items ?? []).map(slim),
    };
  }, { readOnlyHint: true });

  addTool(server, "yadisk_recent", `${SVC}: последние загруженные файлы.`, z.object({
    limit: z.number().int().min(1).max(1000).default(20),
    media_type: z.string().optional().describe("Фильтр по типу: image, video, document, text, audio, archive, spreadsheet и т.п. (можно через запятую)"),
  }), async ({ limit, media_type }) => {
    const r = await call("GET", "/resources/last-uploaded", { limit, media_type });
    return (r.items ?? []).map(slim);
  }, { readOnlyHint: true });

  addTool(server, "yadisk_search", `${SVC}: поиск файлов по подстроке в имени/пути (без учёта регистра). API не имеет полнотекстового поиска, поэтому просматривается плоский список всех файлов (до max_scan штук).`, z.object({
    query: z.string().min(1),
    in_path: z.string().optional().describe("Искать только внутри этой папки"),
    media_type: z.string().optional().describe("Фильтр по типу: image, video, document, text и т.д."),
    max_results: z.number().int().min(1).max(500).default(50),
    max_scan: z.number().int().min(1000).max(20000).default(10000).describe("Сколько файлов максимум просмотреть"),
  }), async ({ query, in_path, media_type, max_results, max_scan }) => {
    const q = query.toLowerCase();
    const prefix = in_path ? diskPath(in_path).replace(/\/?$/, "/") : undefined;
    const found: any[] = [];
    let offset = 0;
    let scanned = 0;
    const page = 1000;
    let exhausted = false;
    while (scanned < max_scan && found.length < max_results) {
      const r = await call("GET", "/resources/files", {
        limit: page,
        offset,
        media_type,
        fields: "items.name,items.path,items.type,items.size,items.mime_type,items.media_type,items.modified,items.public_url",
      });
      const items: any[] = r.items ?? [];
      scanned += items.length;
      for (const it of items) {
        if (prefix && !String(it.path).startsWith(prefix)) continue;
        if (String(it.path).toLowerCase().includes(q)) {
          found.push(slim(it));
          if (found.length >= max_results) break;
        }
      }
      if (items.length < page) {
        exhausted = true;
        break;
      }
      offset += page;
    }
    return { query, scanned, complete: exhausted, results: found };
  }, { readOnlyHint: true });

  addTool(server, "yadisk_metadata", `${SVC}: метаданные файла или папки (размер, даты, md5, публичная ссылка).`, z.object({ path: pathArg }), async ({ path }) => {
    const r = await call("GET", "/resources", { path: diskPath(path), limit: 0 });
    const s = slim(r);
    if (r.type === "dir") s.items_total = r._embedded?.total;
    if (r.public_key) s.public_key = r.public_key;
    return s;
  }, { readOnlyHint: true });

  addTool(server, "yadisk_get_download_link", `${SVC}: прямая ссылка на скачивание файла (папка скачивается zip-архивом). Ссылка временная. Используйте её вместо чтения больших файлов через сервер.`, z.object({ path: pathArg }), async ({ path }) => {
    const r = await call("GET", "/resources/download", { path: diskPath(path) });
    return { href: r.href, method: r.method ?? "GET" };
  }, { readOnlyHint: true });

  addTool(server, "yadisk_read_text", `${SVC}: прочитать текстовый файл (до ${TEXT_LIMIT / 1024} КБ; больше — обрезается). Для бинарных/больших файлов используйте yadisk_get_download_link.`, z.object({ path: pathArg }), async ({ path }) => {
    const meta = await call("GET", "/resources", { path: diskPath(path), fields: "type,size,mime_type,path" });
    if (meta.type === "dir") throw new UserError("Это папка, а не файл");
    const link = await call("GET", "/resources/download", { path: diskPath(path) });
    const res = await fetch(link.href);
    if (!res.ok) throw await httpError(SVC + " (скачивание)", res);
    const { text, truncated } = await readTextLimited(res);
    return [
      `path: ${meta.path}`,
      `size: ${humanSize(meta.size)}, mime: ${meta.mime_type}${truncated ? `, ОБРЕЗАНО до ${TEXT_LIMIT / 1024} КБ` : ""}`,
      "-----",
      text,
    ].join("\n");
  }, { readOnlyHint: true });

  addTool(server, "yadisk_upload_text", `${SVC}: создать/перезаписать текстовый файл (до ${TEXT_LIMIT / 1024} КБ). Для больших файлов — yadisk_upload_from_url.`, z.object({
    path: pathArg,
    content: z.string(),
    overwrite: z.boolean().default(false),
  }), async ({ path, content, overwrite }) => {
    if (textBytes(content) > TEXT_LIMIT) throw new UserError(`Текст больше ${TEXT_LIMIT / 1024} КБ`);
    const up = await call("GET", "/resources/upload", { path: diskPath(path), overwrite });
    const res = await fetch(up.href, { method: up.method ?? "PUT", body: content, headers: { "Content-Type": "text/plain; charset=utf-8" } });
    if (!res.ok) throw await httpError(SVC + " (загрузка)", res);
    return { uploaded: diskPath(path), bytes: textBytes(content) };
  }, { destructiveHint: true });

  addTool(server, "yadisk_upload_from_url", `${SVC}: загрузить файл на Диск по внешнему URL — скачивает сам Яндекс (подходит для больших файлов). Операция асинхронная.`, z.object({
    url: z.string().url(),
    path: pathArg.describe("Куда сохранить, включая имя файла"),
  }), async ({ url, path }) => {
    const r = await call("POST", "/resources/upload", { url, path: diskPath(path) });
    return { path: diskPath(path), ...(opInfo(r) ?? { status: "accepted" }) };
  });

  addTool(server, "yadisk_operation_status", `${SVC}: статус асинхронной операции (загрузка по URL, копирование, перемещение, удаление).`, z.object({
    operation_id: z.string(),
  }), async ({ operation_id }) => call("GET", `/operations/${encodeURIComponent(operation_id)}`), { readOnlyHint: true });

  addTool(server, "yadisk_mkdir", `${SVC}: создать папку (родительская папка должна существовать).`, z.object({ path: pathArg }), async ({ path }) => {
    await call("PUT", "/resources", { path: diskPath(path) });
    return { created: diskPath(path) };
  }, { idempotentHint: true });

  for (const op of ["copy", "move"] as const) {
    addTool(server, `yadisk_${op}`, `${SVC}: ${op === "copy" ? "скопировать" : "переместить/переименовать"} файл или папку.`, z.object({
      from: pathArg,
      to: pathArg.describe("Полный новый путь, включая имя"),
      overwrite: z.boolean().default(false),
    }), async ({ from, to, overwrite }) => {
      const r = await call("POST", `/resources/${op}`, { from: diskPath(from), path: diskPath(to), overwrite });
      return { from: diskPath(from), to: diskPath(to), ...(opInfo(r) ?? { status: "done" }) };
    }, { destructiveHint: op === "move" || undefined });
  }

  addTool(server, "yadisk_delete", `${SVC}: удалить файл или папку. По умолчанию — в корзину (можно восстановить через yadisk_restore).`, z.object({
    path: pathArg,
    permanently: z.boolean().default(false).describe("true — удалить безвозвратно, минуя корзину"),
  }), async ({ path, permanently }) => {
    const r = await call("DELETE", "/resources", { path: diskPath(path), permanently });
    return { deleted: diskPath(path), permanently, ...(opInfo(r) ?? { status: "done" }) };
  }, { destructiveHint: true });

  addTool(server, "yadisk_publish", `${SVC}: опубликовать файл/папку и получить публичную ссылку.`, z.object({ path: pathArg }), async ({ path }) => {
    await call("PUT", "/resources/publish", { path: diskPath(path) });
    const r = await call("GET", "/resources", { path: diskPath(path), fields: "public_url,public_key,path" });
    return { path: r.path, public_url: r.public_url, public_key: r.public_key };
  }, { idempotentHint: true });

  addTool(server, "yadisk_unpublish", `${SVC}: закрыть публичный доступ к файлу/папке.`, z.object({ path: pathArg }), async ({ path }) => {
    await call("PUT", "/resources/unpublish", { path: diskPath(path) });
    return { unpublished: diskPath(path) };
  }, { idempotentHint: true });

  addTool(server, "yadisk_list_trash", `${SVC}: содержимое корзины (с пагинацией).`, z.object({
    path: z.string().default("trash:/").describe('Путь в корзине, по умолчанию "trash:/"'),
    limit: z.number().int().min(1).max(1000).default(100),
    offset: z.number().int().min(0).default(0),
  }), async ({ path, limit, offset }) => {
    const p = path.startsWith("trash:") ? path : "trash:/" + path.replace(/^\/+/, "");
    const r = await call("GET", "/trash/resources", { path: p, limit, offset });
    const e = r._embedded ?? {};
    return { total: e.total, offset: e.offset, items: (e.items ?? []).map(slim) };
  }, { readOnlyHint: true });

  addTool(server, "yadisk_restore", `${SVC}: восстановить файл/папку из корзины (path — путь вида "trash:/имя_с_хешем" из yadisk_list_trash).`, z.object({
    path: z.string(),
    name: z.string().optional().describe("Новое имя при восстановлении"),
    overwrite: z.boolean().default(false),
  }), async ({ path, name, overwrite }) => {
    const p = path.startsWith("trash:") ? path : "trash:/" + path.replace(/^\/+/, "");
    const r = await call("PUT", "/trash/resources/restore", { path: p, name, overwrite });
    return { restored: p, ...(opInfo(r) ?? { status: "done", path: r.href ? decodeURIComponent(String(r.href).split("path=")[1] ?? "") : undefined }) };
  });
}
