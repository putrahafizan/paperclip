import { randomUUID } from "node:crypto";
import {
  definePlugin,
  runWorker,
  type PaperclipPlugin,
  type PluginContext,
  type PluginWebhookInput,
} from "@paperclipai/plugin-sdk";
import type { WaPluginConfig, IncomingWaMessage, WaContext } from "./types.js";
import { sendReply } from "./send-reply.js";
import { PLUGIN_ID, WEBHOOK_KEY } from "./manifest.js";

/** In-memory deduplication set — reset on plugin restart. */
const seenMessageIds = new Set<string>();

let currentCtx: PluginContext | null = null;

async function getConfig(ctx: PluginContext): Promise<WaPluginConfig | null> {
  return await ctx.state.get({ scopeKind: "instance", stateKey: "wa-plugin-config" }) as WaPluginConfig | null;
}

async function getWaContext(ctx: PluginContext, issueId: string): Promise<WaContext | null> {
  return await ctx.state.get({ scopeKind: "issue", scopeId, stateKey: "wa-context" }) as WaContext | null;
}

const plugin: PaperclipPlugin = definePlugin({
  async setup(ctx) {
    currentCtx = ctx;
    ctx.logger.info("WhatsApp OpenClaw plugin setup");

    // Listen for issue.done → reply to WA
    ctx.events.on("issue.updated", async (event) => {
      const payload = event.payload as {
        issueId: string;
        status: string;
        companyId: string;
      };

      if (payload.status !== "done") return;

      const waCtx = await getWaContext(ctx, payload.issueId);
      if (!waCtx) return;

      ctx.logger.info("Issue done, sending WA reply", { issueId: payload.issueId });

      await sendReply(ctx, {
        context: waCtx,
        text: "✅ Issue resolved! Thank you for reaching out 🙏",
      });
    });
  },

  async onHealth() {
    return { status: "ok", message: "WhatsApp OpenClaw plugin ready" };
  },

  async onWebhook(input: PluginWebhookInput) {
    if (input.endpointKey !== WEBHOOK_KEY) {
      throw new Error(`Unknown webhook endpoint: ${input.endpointKey}`);
    }

    const ctx = currentCtx;
    if (!ctx) {
      throw new Error("Plugin context not initialized");
    }

    // Parse incoming payload
    const body = input.parsedBody as IncomingWaMessage | null;
    if (!body?.messageId || !body?.from) {
      ctx.logger.warn("Invalid WA webhook payload", { body });
      return;
    }

    const { from, text, messageId, sessionKey } = body;
    const sender = body.sender ?? from;

    ctx.logger.info("WA webhook received", { from, messageId });

    // Deduplication
    if (seenMessageIds.has(messageId)) {
      ctx.logger.info("Duplicate message ignored", { messageId });
      return;
    }
    seenMessageIds.add(messageId);
    // Keep set bounded
    if (seenMessageIds.size > 10000) seenMessageIds.clear();

    // Load plugin config
    const config = await getConfig(ctx);
    if (!config) {
      ctx.logger.error("WA plugin not configured — set wa-plugin-config in instance state");
      return;
    }

    // Optional verify token check
    if (config.webhookVerifyToken) {
      const token = input.headers?.["x-openclaw-token"] ?? input.headers?.["x-openclaw-token".toLowerCase()];
      if (token !== config.webhookVerifyToken) {
        ctx.logger.warn("Webhook verify token mismatch", { received: token });
        return;
      }
    }

    // Create Paperclip issue
    const title = `[WA] ${sender}: ${text.slice(0, 100)}`;
    const description = [
      `**From:** ${sender} (${from})`,
      `**Session:** ${sessionKey}`,
      `---`,
      text,
    ].join("\n");

    const issue = await ctx.issues.create({
      companyId: config.companyId,
      projectId: config.projectId,
      title,
      description,
      assigneeAgentId: config.openClawAgentId,
    });

    ctx.logger.info("WA issue created", { issueId: issue.id, title });

    // Save WA context on issue so we can reply later
    const waContext: WaContext = {
      from,
      sessionKey,
      openClawApiUrl: config.openClawApiUrl,
      openClawToken: config.openClawToken,
    };
    await ctx.state.set(
      { scopeKind: "issue", scopeId: issue.id, stateKey: "wa-context" },
      waContext,
    );

    // Send acknowledgement to WhatsApp
    await sendReply(ctx, {
      context: waContext,
      text: "Pesan diterima, sedang diproses 🙏",
    });
  },

  async onShutdown() {
    const ctx = currentCtx;
    currentCtx = null;
    seenMessageIds.clear();
    ctx?.logger.info("WhatsApp OpenClaw plugin shutdown");
  },
});

export default plugin;
runWorker(plugin, import.meta.url);
