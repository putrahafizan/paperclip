import type { WaContext } from "./types.js";

const SEND_MESSAGE_PATH = "/api/messages/send";

export interface SendReplyParams {
  context: WaContext;
  text: string;
}

export async function sendReply(
  ctx: {
    http: {
      fetch: (url: string, init?: RequestInit) => Promise<Response>;
    };
    logger: {
      info: (msg: string, data?: Record<string, unknown>) => void;
      warn: (msg: string, data?: Record<string, unknown>) => void;
      error: (msg: string, data?: Record<string, unknown>) => void;
    };
  },
  params: SendReplyParams,
): Promise<void> {
  const { context, text } = params;
  const url = `${context.openClawApiUrl}${SEND_MESSAGE_PATH}`;

  try {
    const response = await ctx.http.fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${context.openClawToken}`,
      },
      body: JSON.stringify({
        to: context.from,
        text,
        sessionKey: context.sessionKey,
        type: "text",
      }),
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "(no body)");
      ctx.logger.warn("OpenClaw send reply failed", {
        status: response.status,
        body,
      });
    } else {
      ctx.logger.info("WA reply sent", { to: context.from, text });
    }
  } catch (err) {
    ctx.logger.error("Failed to send WA reply", {
      error: err instanceof Error ? err.message : String(err),
    });
  }
}
