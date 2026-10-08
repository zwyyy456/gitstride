import { DurableObject } from "cloudflare:workers";
import {
    authenticateManagementRequest,
    ManagementAuthenticationError,
} from "./management-auth";
import type { Env } from "./index";

interface AutomationRecord {
    id: string;
}

export interface AutomationChangeNotifier {
    publish(automationID: string, type: AutomationChangeEventType): Promise<void>;
}

export type AutomationChangeEventType = "project_data_changed" | "automation_changed";

interface AutomationEventMessage {
    type: "ready" | AutomationChangeEventType;
    revision: number;
}

export class AutomationEvents extends DurableObject<Env> {
    async fetch(request: Request): Promise<Response> {
        if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
            return Response.json({ error: "WEBSOCKET_REQUIRED" }, { status: 426 });
        }

        const pair = new WebSocketPair();
        const [client, server] = Object.values(pair);
        this.ctx.acceptWebSocket(server);
        server.serializeAttachment({ tokenID: request.headers.get("X-GitStride-Token-ID") });
        const revision = await this.ctx.storage.get<number>("revision") ?? 0;
        server.send(JSON.stringify(eventMessage("ready", revision)));
        return new Response(null, { status: 101, webSocket: client });
    }

    async closeConnections(): Promise<void> {
        for (const socket of this.ctx.getWebSockets()) socket.close(1008, "Automation disconnected");
    }

    async publish(type: AutomationChangeEventType): Promise<void> {
        const revision = (await this.ctx.storage.get<number>("revision") ?? 0) + 1;
        await this.ctx.storage.put("revision", revision);
        const message = JSON.stringify(eventMessage(type, revision));
        for (const socket of this.ctx.getWebSockets()) {
            const { tokenID } = socket.deserializeAttachment() as { tokenID: string };
            const credential = await this.env.DB.prepare("SELECT id FROM management_tokens WHERE id = ? AND revoked_at IS NULL")
                .bind(tokenID).first();
            if (!credential) { socket.close(1008, "Management access revoked"); continue; }
            try {
                socket.send(message);
            } catch {
                socket.close(1011, "Delivery failed");
            }
        }
    }

    async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
        if (message === "ping") socket.send("pong");
    }

    async webSocketClose(
        socket: WebSocket,
        code: number,
        reason: string,
        wasClean: boolean
    ): Promise<void> {
        socket.close(code, reason);
    }
}

export class DurableObjectAutomationChangeNotifier implements AutomationChangeNotifier {
    constructor(private readonly namespace: DurableObjectNamespace<AutomationEvents>) {}

    async publish(automationID: string, type: AutomationChangeEventType): Promise<void> {
        await this.namespace.getByName(automationID).publish(type);
    }
}

export async function handleAutomationEventsRequest(
    request: Request,
    env: Env
): Promise<Response> {
    if (request.method !== "GET") {
        return Response.json({ error: "METHOD_NOT_ALLOWED" }, { status: 405 });
    }
    try {
        const identity = await authenticateManagementRequest(request, env.DB);
        const automation = await env.DB.prepare(
            "SELECT id FROM project_automations WHERE user_id = ?"
        ).bind(identity.userID).first<AutomationRecord>();
        if (!automation) {
            return Response.json({ error: "AUTOMATION_NOT_FOUND" }, { status: 404 });
        }
        const authorizedRequest = new Request(request);
        authorizedRequest.headers.set("X-GitStride-Token-ID", identity.tokenID);
        return env.AUTOMATION_EVENTS.getByName(automation.id).fetch(authorizedRequest);
    } catch (error) {
        if (error instanceof ManagementAuthenticationError) {
            return Response.json({ error: error.message }, { status: 401 });
        }
        return Response.json({ error: "AUTOMATION_EVENTS_UNAVAILABLE" }, { status: 503 });
    }
}

function eventMessage(
    type: AutomationEventMessage["type"],
    revision: number
): AutomationEventMessage {
    return { type, revision };
}
