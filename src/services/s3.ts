import type { McpServer } from "@modelcontextprotocol/server";
import { AwsClient } from "aws4fetch";
import { z } from "zod";
import type { Env } from "../env";
import { addTool, httpError, humanSize, readTextLimited, TEXT_LIMIT, textBytes, UserError } from "../util";

export const S3_PRESETS: Record<string, { name: string; endpoint: string; region: string }> = {
  yandex: { name: "Yandex Object Storage", endpoint: "https://storage.yandexcloud.net", region: "ru-central1" },
  selectel: { name: "Selectel S3", endpoint: "https://s3.ru-1.storage.selcloud.ru", region: "ru-1" },
  vk: { name: "VK Cloud Object Storage", endpoint: "https://hb.ru-msk.vkcloud-storage.ru", region: "ru-msk" },
  cloudru: { name: "Cloud.ru Object Storage", endpoint: "https://s3.cloud.ru", region: "ru-central-1" },
};

const ALIASES: Record<string, string> = {
  "yandex-cloud": "yandex", yc: "yandex", yandexcloud: "yandex",
  selcloud: "selectel",
  "vk-cloud": "vk", vkcloud: "vk", mcs: "vk",
  "cloud.ru": "cloudru", sbercloud: "cloudru",
};

function decodeXml(s: string): string {
  return s
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&amp;/g, "&");
}

function tag(xml: string, name: string): string | undefined {
  const m = xml.match(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`));
  return m ? decodeXml(m[1]) : undefined;
}

function blocks(xml: string, name: string): string[] {
  return [...xml.matchAll(new RegExp(`<${name}>([\\s\\S]*?)</${name}>`, "g"))].map((m) => m[1]);
}

function encKey(key: string): string {
  return key.split("/").map(encodeURIComponent).join("/");
}

export function registerS3(server: McpServer, env: Env): void {
  if (!env.S3_ACCESS_KEY || !env.S3_SECRET_KEY) return;
  const providerRaw = (env.S3_PROVIDER ?? "").trim().toLowerCase();
  const provider = ALIASES[providerRaw] ?? providerRaw;
  const preset = S3_PRESETS[provider];
  const endpoint = (env.S3_ENDPOINT || preset?.endpoint || "").replace(/\/+$/, "");
  const region = env.S3_REGION || preset?.region || "us-east-1";
  const label = `S3 (${preset?.name ?? (endpoint || "не настроено")})`;

  if (!endpoint) {
    // Misconfigured: register a single diagnostic tool instead of crashing.
    addTool(server, "s3_config_error", `${label}: S3 настроен неверно — объясняет, что исправить.`, z.object({}), async () => {
      throw new UserError(`Неизвестный S3_PROVIDER "${env.S3_PROVIDER ?? ""}" и не задан S3_ENDPOINT. Допустимые провайдеры: ${Object.keys(S3_PRESETS).join(", ")}.`);
    }, { readOnlyHint: true });
    return;
  }

  const aws = new AwsClient({ accessKeyId: env.S3_ACCESS_KEY, secretAccessKey: env.S3_SECRET_KEY, service: "s3", region });

  function url(bucket?: string, key?: string, q: Record<string, string | number | undefined> = {}): URL {
    let p = endpoint + "/";
    if (bucket) p += encodeURIComponent(bucket) + (key !== undefined ? "/" + encKey(key) : "");
    const u = new URL(p);
    for (const [k, v] of Object.entries(q)) if (v !== undefined && v !== "") u.searchParams.set(k, String(v));
    return u;
  }

  async function req(method: string, u: URL, init: RequestInit = {}): Promise<Response> {
    const res = await aws.fetch(u.toString(), { method, ...init });
    if (!res.ok) {
      const err = await httpError(label, res);
      const code = err.message.match(/<Code>([^<]+)<\/Code>/)?.[1];
      const msg = err.message.match(/<Message>([^<]+)<\/Message>/)?.[1];
      if (code) throw new UserError(`${label}: HTTP ${res.status} — ${code}${msg ? `: ${msg}` : ""}`);
      throw err;
    }
    return res;
  }

  const bucketArg = z.string().min(1).describe("Имя бакета");
  const keyArg = z.string().min(1).describe('Ключ объекта, например "docs/readme.txt"');

  addTool(server, "s3_list_buckets", `${label}: список бакетов.`, z.object({}), async () => {
    const xml = await (await req("GET", url())).text();
    return {
      endpoint,
      region,
      buckets: blocks(xml, "Bucket").map((b) => ({ name: tag(b, "Name"), created: tag(b, "CreationDate") })),
    };
  }, { readOnlyHint: true });

  addTool(server, "s3_list_objects", `${label}: объекты в бакете (ListObjectsV2) с префиксом, «папками» через delimiter и пагинацией через continuation_token.`, z.object({
    bucket: bucketArg,
    prefix: z.string().optional(),
    delimiter: z.string().default("/").describe('"/" — показывать «папки» отдельно; пустая строка — плоский список'),
    max_keys: z.number().int().min(1).max(1000).default(100),
    continuation_token: z.string().optional(),
  }), async ({ bucket, prefix, delimiter, max_keys, continuation_token }) => {
    const xml = await (await req("GET", url(bucket, undefined, {
      "list-type": 2, prefix, delimiter: delimiter || undefined, "max-keys": max_keys, "continuation-token": continuation_token,
    }))).text();
    return {
      bucket,
      prefix: prefix ?? "",
      is_truncated: tag(xml, "IsTruncated") === "true",
      next_continuation_token: tag(xml, "NextContinuationToken"),
      folders: blocks(xml, "CommonPrefixes").map((b) => tag(b, "Prefix")),
      objects: blocks(xml, "Contents").map((b) => {
        const size = Number(tag(b, "Size") ?? 0);
        return { key: tag(b, "Key"), size, size_human: humanSize(size), modified: tag(b, "LastModified"), etag: tag(b, "ETag")?.replace(/"/g, "") };
      }),
    };
  }, { readOnlyHint: true });

  addTool(server, "s3_get_object", `${label}: прочитать текстовый объект (до ${TEXT_LIMIT / 1024} КБ, больше — обрезается). Для больших/бинарных — s3_presigned_url.`, z.object({
    bucket: bucketArg,
    key: keyArg,
  }), async ({ bucket, key }) => {
    const res = await req("GET", url(bucket, key), { headers: { Range: `bytes=0-${TEXT_LIMIT - 1}` } });
    const total = res.headers.get("Content-Range")?.split("/")[1] ?? res.headers.get("Content-Length") ?? undefined;
    const { text, truncated } = await readTextLimited(res);
    const isTrunc = truncated || (total !== undefined && total !== "*" && Number(total) > TEXT_LIMIT);
    return [
      `s3://${bucket}/${key}`,
      `size: ${total ? humanSize(Number(total)) : "?"}, content-type: ${res.headers.get("Content-Type") ?? "?"}${isTrunc ? `, ОБРЕЗАНО до ${TEXT_LIMIT / 1024} КБ` : ""}`,
      "-----",
      text,
    ].join("\n");
  }, { readOnlyHint: true });

  addTool(server, "s3_put_object", `${label}: записать текстовый объект (до ${TEXT_LIMIT / 1024} КБ). Для больших файлов — s3_presigned_url с method=PUT.`, z.object({
    bucket: bucketArg,
    key: keyArg,
    content: z.string(),
    content_type: z.string().default("text/plain; charset=utf-8"),
  }), async ({ bucket, key, content, content_type }) => {
    if (textBytes(content) > TEXT_LIMIT) throw new UserError(`Текст больше ${TEXT_LIMIT / 1024} КБ`);
    const res = await req("PUT", url(bucket, key), { body: content, headers: { "Content-Type": content_type } });
    return { written: `s3://${bucket}/${key}`, bytes: textBytes(content), etag: res.headers.get("ETag")?.replace(/"/g, "") };
  }, { destructiveHint: true });

  addTool(server, "s3_delete_object", `${label}: удалить объект (безвозвратно, если в бакете не включено версионирование).`, z.object({
    bucket: bucketArg,
    key: keyArg,
  }), async ({ bucket, key }) => {
    await req("DELETE", url(bucket, key));
    return { deleted: `s3://${bucket}/${key}` };
  }, { destructiveHint: true, idempotentHint: true });

  addTool(server, "s3_presigned_url", `${label}: подписанная ссылка (GET — скачать, PUT — загрузить напрямую в хранилище, минуя сервер). Ссылка даёт доступ любому, у кого она есть, до истечения срока.`, z.object({
    bucket: bucketArg,
    key: keyArg,
    method: z.enum(["GET", "PUT"]).default("GET"),
    expires_seconds: z.number().int().min(60).max(604800).default(3600),
  }), async ({ bucket, key, method, expires_seconds }) => {
    const u = url(bucket, key, { "X-Amz-Expires": expires_seconds });
    const signed = await aws.sign(u.toString(), { method, aws: { signQuery: true } });
    return {
      url: signed.url,
      method,
      expires_in_seconds: expires_seconds,
      hint: method === "PUT" ? `curl -X PUT --upload-file ./file '${signed.url}'` : undefined,
    };
  }, { readOnlyHint: true });
}
