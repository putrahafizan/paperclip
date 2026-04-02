/**
 * Configuration shape stored in plugin instance state under key "wa-plugin-config".
 */
export interface WaPluginConfig {
  /** ID of the OpenClaw agent to assign incoming WA issues to. */
  openClawAgentId: string;
  /** Paperclip company ID to operate within. */
  companyId: string;
  /** Base HTTP URL of the OpenClaw instance (e.g. http://localhost:18789). */
  openClawApiUrl: string;
  /** Bearer token for OpenClaw API authentication. */
  openClawToken: string;
  /** Optional project ID to create issues in. Defaults to first project in company. */
  projectId?: string;
  /** Optional verify token expected in x-openclaw-token header. */
  webhookVerifyToken?: string;
}

/** Shape of the inbound webhook payload sent by OpenClaw. */
export interface IncomingWaMessage {
  from: string;
  text: string;
  messageId: string;
  sessionKey: string;
  sender?: string;
}

/** Context saved per-issue so we know where to reply when the issue is done. */
export interface WaContext {
  from: string;
  sessionKey: string;
  openClawApiUrl: string;
  openClawToken: string;
}
