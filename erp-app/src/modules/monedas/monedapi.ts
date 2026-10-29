import { after } from "next/server";
import type { Moneda } from "@/lib/monedas";
import { createAdminClient } from "@/lib/supabase/admin";
import { argsRpc } from "@/lib/supabase/rpc";
import { respuestaMonedapiSchema } from "./types";

const FUENTES: [Exclude<Moneda, "ARS">, string][] = [
  ["USD_OFICIAL", "https://monedapi.ar/api/v2/usd/oficial"],
  ["USD_BLUE", "https://monedapi.ar/api/v2/usd/blue"],
  ["EUR", "https://monedapi.ar/api/v2/eur/bna"],
];

// Lo pide y lo guarda el servidor con `service_role`: el número nunca pasa por el
// navegador (decisiones/monedas.md → Tipos de cambio). Si toca lo decide la base:
// una consulta por hora, o por minuto con el botón, en todo el sistema.
export async function consultarMonedapi(forzada: boolean): Promise<"reciente" | "ok" | "falla"> {
  const admin = createAdminClient();
  const { data: consulta, error } = await admin.rpc("monedas_reservar_consulta", { p_forzada: forzada });
  if (error) return "falla";
  if (!consulta) return "reciente";

  const resultados = await Promise.allSettled(
    FUENTES.map(async ([moneda, url]) => {
      const res = await fetch(url, { cache: "no-store", signal: AbortSignal.timeout(5000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const r = respuestaMonedapiSchema.parse(await res.json());
      const { error } = await admin.rpc("monedas_guardar_monedapi", {
        p_moneda: moneda,
        p_valor: r.sell,
        p_fecha: r.updatedAt,
      });
      if (error) throw new Error(error.message);
    })
  );
  const fallas = resultados.flatMap((r, i) =>
    r.status === "rejected" ? [`${FUENTES[i][0]}: ${r.reason instanceof Error ? r.reason.message : String(r.reason)}`] : []
  );

  await admin.rpc(
    "monedas_cerrar_consulta",
    argsRpc<"monedas_cerrar_consulta">({ p_id: consulta, p_error: fallas.length ? fallas.join(" · ") : null })
  );
  return fallas.length ? "falla" : "ok";
}

// Cada hora, sin cron: la página que se abre después de la hora lo pide, una vez
// enviada la respuesta, así nadie espera a MonedAPI. Lo que trae se ve en la
// próxima navegación.
export function pedirSiHaceFalta(ultimaConsulta: string | null) {
  if (ultimaConsulta && Date.now() - new Date(ultimaConsulta).getTime() < 60 * 60 * 1000) return;
  after(() => consultarMonedapi(false));
}
