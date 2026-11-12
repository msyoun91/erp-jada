import { rpc } from "@/lib/portal";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export async function POST(request: Request) {
  const { huella, version, dispositivo } = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (typeof huella !== "string" || !/^[0-9a-f]{64}$/.test(huella) || !Number.isInteger(version) || typeof dispositivo !== "string" || !UUID.test(dispositivo)) {
    return Response.json({ error: "datos" }, { status: 400 });
  }
  try {
    await rpc("portal_visitar", { p_huella: huella, p_version: version, p_dispositivo: dispositivo });
    return new Response(null, { status: 204 });
  } catch {
    return Response.json({ error: "portal" }, { status: 502 });
  }
}
