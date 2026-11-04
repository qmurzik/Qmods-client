/**
 * Облако Mail.ru — НЕОФИЦИАЛЬНЫЙ API (best effort).
 *
 * Протокол повторяет rclone backend/mailru (https://github.com/rclone/rclone/tree/master/backend/mailru):
 *  - OAuth password grant на https://o2.mail.ru/token с client_id=cloud-win;
 *  - JSON-эндпоинты /api/m1/* на https://cloud.mail.ru (access_token в query);
 *  - бинарный протокол на meta-сервере (адрес выдаёт https://dispatcher.cloud.mail.ru/m)
 *    для создания папок и перемещения;
 *  - сервер скачивания выдаёт https://dispatcher.cloud.mail.ru/d.
 * Mail.ru может изменить всё это без предупреждения.
 */
import type { McpServer } from "@modelcontextprotocol/server";
import { z } from "zod";
import type { Env } from "../env";
import { addTool, humanSize, UserError } from "../util";

const SVC = "Облако Mail.ru (неофициальный API)";
const API = "https://cloud.mail.ru";
const OAUTH_URL = "https://o2.mail.ru/token";
const DISPATCHER = "https://dispatcher.cloud.mail.ru";
const CLIENT_ID = "cloud-win";
const PUBLIC_LINK = "https://cloud.mail.ru/public/";
const FORM = "application/x-www-form-urlencoded";
const UA = "ru-files-mcp/1.0";

// Binary protocol (see rclone backend/mailru/api/bin.go)
const OP_RENAME = 105;
const OP_CREATE_FOLDER = 106;
const MKDIR_RESULTS: Record<number, string> = {
  1: "родительская папка не существует",
  4: "папка уже существует",
  9: "уже существует (отличается регистр)",
  10: "недопустимое имя",
};
const MOVE_RESULTS: Record<number, string> = {
  1: "исходный объект не найден",
  4: "объект с таким именем уже существует",
};

type Token = { access: string; expires: number };
// Per-isolate token cache (Workers isolates live across requests).
const tokenCache = new Map<string, Token>();

class BinWriter {
  private parts: number[] = [];
  uvarint(v: number): this {
    let n = BigInt(v);
    do {
      let b = Number(n & 0x7fn);
      n >>= 7n;
      if (n > 0n) b |= 0x80;
      this.parts.push(b);
    } while (n > 0n);
    return this;
  }
  string(s: string): this {
    const b = new TextEncoder().encode(s);
    this.uvarint(b.length + 1);
    for (const x of b) this.parts.push(x);
    this.parts.push(0);
    return this;
  }
  bytes(): Uint8Array {
    return new Uint8Array(this.parts);
  }
}

function normPath(p?: string): string {
  if (!p) return "/";
  let s = p.trim().replace(/\\/g, "/");
  if (!s.startsWith("/")) s = "/" + s;
  if (s.length > 1) s = s.replace(/\/+$/, "");
  return s;
}

function slim(it: any) {
  const out: any = {
    name: it.name,
    path: it.home,
    type: it.type ?? it.kind,
  };
  if (it.size !== undefined) {
    out.size = it.size;
    out.size_human = humanSize(it.size);
  }
  if (it.mtime) out.modified = new Date(Number(it.mtime) * 1000).toISOString();
  if (it.hash) out.hash = it.hash;
  if (it.weblink) out.public_url = PUBLIC_LINK + it.weblink;
  if (it.count) out.count = it.count;
  return out;
}

export function registerMailru(server: McpServer, env: Env): void {
  const email = env.MAILRU_EMAIL;
  const password = env.MAILRU_APP_PASSWORD;
  if (!email || !password) return;

  async function login(force = false): Promise<string> {
    const cached = tokenCache.get(email!);
    if (!force && cached && cached.expires > Date.now() + 60_000) return cached.access;
    const body = new URLSearchParams({ grant_type: "password", client_id: CLIENT_ID, username: email!, password: password! });
    const res = await fetch(OAUTH_URL, { method: "POST", body, headers: { "Content-Type": FORM, "User-Agent": UA } });
    const j: any = await res.json().catch(() => ({}));
    if (!res.ok || !j.access_token) {
      tokenCache.delete(email!);
      const why = j.error_description || j.error || `HTTP ${res.status}`;
      throw new UserError(
        `${SVC}: не удалось войти (${why}). Проверьте MAILRU_EMAIL и что MAILRU_APP_PASSWORD — пароль для внешнего приложения (id.mail.ru → Безопасность → Пароли для внешних приложений).`,
      );
    }
    const expires = Date.now() + (Number(j.expires_in) || 3600) * 1000;
    tokenCache.set(email!, { access: j.access_token, expires });
    return j.access_token;
  }

  /** Runs fn with a token, retrying once with a fresh login on 401/403. */
  async function withToken<T>(fn: (token: string) => Promise<Response>, parse: (res: Response) => Promise<T>): Promise<T> {
    let token = await login();
    let res = await fn(token);
    if (res.status === 401 || res.status === 403) {
      token = await login(true);
      res = await fn(token);
    }
    if (!res.ok) throw await mailruError(res);
    return parse(res);
  }

  async function mailruError(res: Response): Promise<UserError> {
    const text = await res.text().catch(() => "");
    let msg = `HTTP ${res.status}`;
    try {
      const j = JSON.parse(text);
      const home = j?.body?.home?.error ?? j?.body?.weblink?.error;
      if (home === "not_exists") msg = "объект не найден";
      else if (home === "exists") msg = "объект уже существует";
      else if (home) msg += ` — ${home}`;
      else if (j?.body?.error) msg += ` — ${j.body.error}`;
    } catch {
      if (text) msg += ` — ${text.slice(0, 300)}`;
    }
    return new UserError(`${SVC}: ${msg}`);
  }

  function m1(method: "GET" | "POST", path: string, token: string, query: Record<string, string> = {}, form?: Record<string, string>) {
    const u = new URL(API + path);
    u.searchParams.set("access_token", token);
    for (const [k, v] of Object.entries(query)) u.searchParams.set(k, v);
    return fetch(u, {
      method,
      headers: { "Content-Type": FORM, Accept: "application/json", "User-Agent": UA },
      body: form ? new URLSearchParams(form) : undefined,
    });
  }

  async function dispatch(kind: "m" | "d"): Promise<string> {
    const res = await fetch(`${DISPATCHER}/${kind}`, { headers: { "User-Agent": UA } });
    if (!res.ok) throw new UserError(`${SVC}: диспетчер вернул HTTP ${res.status}`);
    const word = (await res.text()).trim().split(/\s+/)[0];
    if (!word) throw new UserError(`${SVC}: пустой ответ диспетчера`);
    return word;
  }

  async function binCall(payload: Uint8Array): Promise<number> {
    const meta = await dispatch("m");
    return withToken(
      (token) => {
        const u = new URL(meta);
        u.searchParams.set("client_id", CLIENT_ID);
        u.searchParams.set("token", token);
        return fetch(u, { method: "POST", body: payload, headers: { "Content-Type": FORM, "User-Agent": UA } });
      },
      async (res) => {
        const buf = new Uint8Array(await res.arrayBuffer());
        return buf.length ? buf[0] : -1;
      },
    );
  }

  const pathArg = z.string().describe('Путь в Облаке, например "/Документы/file.pdf". Корень — "/"');
  const note = " ВНИМАНИЕ: API неофициальный (как в rclone), может перестать работать без предупреждения.";

  addTool(server, "mailru_list", `${SVC}: содержимое папки (с пагинацией).${note}`, z.object({
    path: pathArg.default("/"),
    limit: z.number().int().min(1).max(1000).default(100),
    offset: z.number().int().min(0).default(0),
  }), async ({ path, limit, offset }) => {
    const p = normPath(path);
    const j: any = await withToken(
      (t) => m1("POST", "/api/m1/folder", t, { offset: String(offset), limit: String(limit) }, { home: p }),
      (r) => r.json(),
    );
    const b = j.body ?? {};
    if (b.kind === "file" || b.type === "file") return { item: slim(b), note: "Это файл, а не папка" };
    const total = (b.count?.folders ?? 0) + (b.count?.files ?? 0);
    return {
      path: b.home ?? p,
      total,
      offset,
      has_more: offset + (b.list?.length ?? 0) < total,
      items: (b.list ?? []).map(slim),
    };
  }, { readOnlyHint: true });

  addTool(server, "mailru_metadata", `${SVC}: метаданные файла или папки.${note}`, z.object({ path: pathArg }), async ({ path }) => {
    const j: any = await withToken((t) => m1("GET", "/api/m1/file", t, { home: normPath(path), offset: "0", limit: "0" }), (r) => r.json());
    return slim(j.body ?? {});
  }, { readOnlyHint: true });

  addTool(server, "mailru_download_link", `${SVC}: прямая ссылка на скачивание файла. Ссылка содержит временный access-токен аккаунта (действует ~несколько часов) — не публикуйте её; для передачи третьим лицам используйте mailru_publish.${note}`, z.object({ path: pathArg }), async ({ path }) => {
    const p = normPath(path);
    const meta: any = await withToken((t) => m1("GET", "/api/m1/file", t, { home: p, offset: "0", limit: "0" }), (r) => r.json());
    if ((meta.body?.kind ?? meta.body?.type) === "folder") throw new UserError("Это папка — скачать можно только файл");
    const server = (await dispatch("d")).replace(/\/?$/, "/");
    const token = await login();
    const u = server + encodeURIComponent(p.replace(/^\/+/, "")) + `?client_id=${CLIENT_ID}&token=${encodeURIComponent(token)}`;
    return { href: u, size_human: humanSize(meta.body?.size), warning: "Ссылка содержит токен доступа — не делитесь ею." };
  }, { readOnlyHint: true });

  addTool(server, "mailru_mkdir", `${SVC}: создать папку (родительская должна существовать).${note}`, z.object({ path: pathArg }), async ({ path }) => {
    const p = normPath(path);
    const w = new BinWriter().uvarint(OP_CREATE_FOLDER).uvarint(0).string(p).uvarint(0);
    const status = await binCall(w.bytes());
    if (status !== 0) throw new UserError(`${SVC}: mkdir — ${MKDIR_RESULTS[status] ?? `код ${status}`}`);
    return { created: p };
  }, { idempotentHint: true });

  addTool(server, "mailru_move", `${SVC}: переместить или переименовать файл/папку (to — полный новый путь, включая имя).${note}`, z.object({
    from: pathArg,
    to: pathArg,
  }), async ({ from, to }) => {
    const src = normPath(from);
    const dst = normPath(to);
    const w = new BinWriter().uvarint(OP_RENAME).uvarint(0).string(src).uvarint(0).string(dst).uvarint(0);
    const status = await binCall(w.bytes());
    if (status !== 0) throw new UserError(`${SVC}: move — ${MOVE_RESULTS[status] ?? `код ${status}`}`);
    return { from: src, to: dst };
  }, { destructiveHint: true });

  addTool(server, "mailru_delete", `${SVC}: удалить файл или папку (попадает в корзину Облака).${note}`, z.object({ path: pathArg }), async ({ path }) => {
    const p = normPath(path);
    if (p === "/") throw new UserError("Нельзя удалить корень");
    const j: any = await withToken((t) => m1("POST", "/api/m1/file/remove", t, {}, { home: p }), (r) => r.json());
    if (j.status && j.status !== 200) throw new UserError(`${SVC}: delete — код ${j.status}`);
    return { deleted: p };
  }, { destructiveHint: true });

  addTool(server, "mailru_publish", `${SVC}: опубликовать файл/папку и получить публичную ссылку cloud.mail.ru/public/...${note}`, z.object({ path: pathArg }), async ({ path }) => {
    const p = normPath(path);
    const j: any = await withToken(
      (t) => m1("POST", "/api/m1/file/publish", t, {}, { home: p, email: email!, "x-email": email! }),
      (r) => r.json(),
    );
    if (!j.body) throw new UserError(`${SVC}: сервер вернул пустую ссылку`);
    return { path: p, public_url: PUBLIC_LINK + j.body };
  }, { idempotentHint: true });
}
