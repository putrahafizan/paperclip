import type { PaperclipPluginManifestV1 } from "@paperclipai/plugin-sdk";

const PLUGIN_ID = "paperclip.whatsapp-openclaw";
const PLUGIN_VERSION = "0.1.0";
const WEBHOOK_KEY = "wa-incoming";

const manifest: PaperclipPluginManifestV1 = {
  id: PLUGIN_ID,
  apiVersion: 1,
  version: PLUGIN_VERSION,
  displayName: "WhatsApp via OpenClaw",
  description:
    "Receives WhatsApp messages via OpenClaw webhook, creates a Paperclip issue, assigns to the OpenClaw agent, and replies when the issue is marked done.",
  author: "Paperclip",
  categories: ["automation", "connector"],
  capabilities: [
    "webhooks.receive",
    "issues.create",
    "issues.read",
    "issues.update",
    "events.subscribe",
    "http.outbound",
    "plugin.state.read",
    "plugin.state.write",
    "agents.read",
    "companies.read",
    "projects.read",
  ],
  entrypoints: {
    worker: "./dist/worker.js",
  },
  instanceConfigSchema: {
    type: "object",
    properties: {
      openClawAgentId: {
        type: "string",
        title: "OpenClaw Agent ID",
        description: "The Paperclip agent ID to assign incoming WhatsApp issues to.",
      },
      companyId: {
        type: "string",
        title: "Company ID",
        description: "The Paperclip company ID to operate within.",
      },
      openClawApiUrl: {
        type: "string",
        title: "OpenClaw API URL",
        description: "Base URL of the OpenClaw instance (e.g. http://localhost:18789).",
        default: "http://localhost:18789",
      },
      openClawToken: {
        type: "string",
        title: "OpenClaw API Token",
        description: "Bearer token for OpenClaw API authentication.",
      },
      projectId: {
        type: "string",
        title: "Project ID (optional)",
        description: "Optional project ID to create issues in. Defaults to first project in company.",
      },
      webhookVerifyToken: {
        type: "string",
        title: "Webhook Verify Token (optional)",
        description: "Optional token expected in x-openclaw-token header for webhook verification.",
      },
    },
  },
  webhooks: [
    {
      endpointKey: WEBHOOK_KEY,
      displayName: "WhatsApp Incoming",
      description:
        "Receives inbound WhatsApp messages from OpenClaw. Set this URL in your OpenClaw configuration.",
    },
  ],
};

export default manifest;
export { PLUGIN_ID, PLUGIN_VERSION, WEBHOOK_KEY };
