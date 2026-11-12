import { rpc } from "@/lib/portal";

type Moneda = { moneda: string; valor: number; fecha: string; referencia: boolean };

export async function POST(request: Request) {
  const { huella } = (await request.json().catch(() => ({}))) as { huella?: unknown };
  if (typeof huella !== "string" || !/^[0-9a-f]{64}$/.test(huella)) return Response.json({ error: "huella" }, { status: 400 });
  try {
    const [copia, monedas] = await Promise.all([
      rpc<string | null>("portal_leer", { p_huella: huella }),
      rpc<Moneda[]>("portal_monedas_leer", {}),
    ]);
    return Response.json({ copia, monedas });
  } catch {
    return Response.json({ error: "portal" }, { status: 502 });
  }
}
