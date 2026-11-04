import type { McpServer } from "@modelcontextprotocol/server";
import { z } from "zod";

/** Max size of text we read/write through the worker. */
export const TEXT_LIMIT = 1024 * 1024; // 1 MiB

export type ToolResult = {
  content: { type: "text"; text: string }[];
  isError?: boolean;
};

/** Error that is shown to the model as a plain message. */
export class UserError extends Error {}

export function ok(data: unknown): ToolResult {
  const text = typeof data === "string" ? data : JSON.stringify(data, null, 2);
  return { content: [{ type: "text", text }] };
}

export function fail(message: string): ToolResult {
  return { content: [{ type: "text", text: `Ошибка: ${message}` }], isError: true };
}

type Annotations = {
  readOnlyHint?: boolean;
  destructiveHint?: boolean;
  idempotentHint?: boolean;
  openWorldHint?: boolean;
};

/**
 * Registers a tool whose handler never throws: every exception is turned into
 * a readable error result.
 */
export function addTool<S extends z.ZodObject<z.ZodRawShape>>(
  server: McpServer,
  name: string,
  description: string,
  schema: S,
  handler: (args: z.infer<S>) => Promise<unknown>,
  annotations: Annotations = {},
): void {
  server.registerTool(
    name,
    {
      description,
      inputSchema: schema,
      annotations: { openWorldHint: true, ...annotations },
    },
    (async (args: z.infer<S>) => {
      try {
        const res = await handler(args);
        return ok(res);
      } catch (e) {
        return fail(e instanceof Error ? e.message : String(e));
      }
    }) as never,
  );
}

/** Reads a response body as text, refusing more than `limit` bytes. */
export async function readTextLimited(res: Response, limit = TEXT_LIMIT): Promise<{ text: string; truncated: boolean }> {
  if (!res.body) return { text: "", truncated: false };
  const reader = res.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  let truncated = false;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (size + value.byteLength > limit) {
      chunks.push(value.subarray(0, limit - size));
      size = limit;
      truncated = true;
      await reader.cancel();
      break;
    }
    chunks.push(value);
    size += value.byteLength;
  }
  const buf = new Uint8Array(size);
  let off = 0;
  for (const c of chunks) {
    buf.set(c, off);
    off += c.byteLength;
  }
  return { text: new TextDecoder("utf-8").decode(buf), truncated };
}

/** Builds a readable message from a failed HTTP response. */
export async function httpError(service: string, res: Response): Promise<UserError> {
  let detail = "";
  try {
    const { text } = await readTextLimited(res, 4096);
    try {
      const j = JSON.parse(text);
      detail = j.message || j.description || j.error_description || j.error || text;
      if (typeof detail !== "string") detail = JSON.stringify(detail);
    } catch {
      detail = text.replace(/\s+/g, " ").trim();
    }
  } catch {
    /* ignore */
  }
  return new UserError(`${service}: HTTP ${res.status}${detail ? ` — ${detail.slice(0, 500)}` : ""}`);
}

export function textBytes(s: string): number {
  return new TextEncoder().encode(s).byteLength;
}

export function humanSize(n?: number): string | undefined {
  if (n === undefined || n === null) return undefined;
  const u = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
  let i = 0;
  let v = n;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(i ? 1 : 0)} ${u[i]}`;
}
