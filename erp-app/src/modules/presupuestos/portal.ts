import { after } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { createAdminClient } from "@/lib/supabase/admin";
import type { Database as Portal } from "@/lib/supabase/portal.types";
import { cifrar, huellaDe } from "./cifrado";

const copiaSchema = z.object({
  revision: z.number().int().positive(),
  estado: z.string(),
  versiones: z.array(z.object({ numero: z.number().int() })).optional(),
});

function portal() {
  const url = process.env.PORTAL_SUPABASE_URL;
  const key = process.env.PORTAL_SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Falta PORTAL_SUPABASE_URL o PORTAL_SUPABASE_SERVICE_ROLE_KEY");
  return createClient<Portal>(url, key, { auth: { persistSession: false } });
}

type Admin = ReturnType<typeof createAdminClient>;
type Cliente = ReturnType<typeof portal>;

// Lo que la base dice que falta: armar, cifrar, llevar y confirmar. Un link que falla no frena a los demás; queda
// pendiente y se reintenta en la próxima pasada.
async function copiarPendientes(admin: Admin, p: Cliente): Promise<string[]> {
  const { data: pendientes, error } = await admin.rpc("presupuestos_portal_pendientes");
  if (error) return [`pendientes: ${error.message}`];

  const fallas: string[] = [];
  for (const { link_id, llave } of pendientes) {
    try {
      const { data, error } = await admin.rpc("presupuestos_portal_copia", { p_link: link_id });
      if (error) throw new Error(error.message);
      if (data === null) continue;
      const copia = copiaSchema.parse(data);
      const cortado = copia.estado === "cortado";
      const versiones = copia.versiones?.map((v) => v.numero) ?? [];

      const enviado = await p.rpc("portal_copiar", {
        p_huella: huellaDe(llave),
        p_revision: copia.revision,
        p_copia: cortado ? null : cifrar(llave, JSON.stringify(data)),
        p_versiones: versiones,
      });
      if (enviado.error) throw new Error(enviado.error.message);

      const confirmado = await admin.rpc("presupuestos_portal_copiada", {
        p_link: link_id,
        p_revision: copia.revision,
        p_versiones: versiones,
      });
      if (confirmado.error) throw new Error(confirmado.error.message);
    } catch (e) {
      fallas.push(`${link_id}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  return fallas;
}

async function leerVisitas(admin: Admin, p: Cliente): Promise<string[]> {
  const { data: links, error } = await admin.rpc("presupuestos_portal_links");
  if (error) return [`links: ${error.message}`];
  if (!links.length) return [];

  const linkDe = new Map(links.map((l) => [huellaDe(l.llave), l.link_id]));
  const leidas = await p.rpc("portal_visitas_de", { p_huellas: [...linkDe.keys()] });
  if (leidas.error) return [`visitas: ${leidas.error.message}`];
  if (!leidas.data.length) return [];

  const { error: guardado } = await admin.rpc("presupuestos_portal_visitas", {
    p_visitas: leidas.data.map(({ huella, ...v }) => ({ link: linkDe.get(huella) ?? null, ...v })),
  });
  return guardado ? [`guardar visitas: ${guardado.message}`] : [];
}

async function copiarMonedas(admin: Admin, p: Cliente): Promise<string[]> {
  const { data, error } = await admin.rpc("presupuestos_portal_monedas");
  if (error) return [`monedas: ${error.message}`];
  const { error: enviado } = await p.rpc("portal_monedas_guardar", { p_monedas: data });
  return enviado ? [`monedas al portal: ${enviado.message}`] : [];
}

// shortcut: la hora se cuenta por proceso del servidor; con varias instancias se lee algo más seguido. Si molesta, una
// reserva en la base como monedas_reservar_consulta.
let ultimaLectura = 0;

// Copia lo pendiente siempre; visitas y tipos de cambio, una vez por hora o cuando se fuerza (el botón).
export async function sincronizarPortal(forzada: boolean): Promise<"ok" | "falla"> {
  try {
    const admin = createAdminClient();
    const p = portal();
    const fallas = await copiarPendientes(admin, p);
    if (forzada || Date.now() - ultimaLectura >= 60 * 60 * 1000) {
      ultimaLectura = Date.now();
      fallas.push(...(await leerVisitas(admin, p)), ...(await copiarMonedas(admin, p)));
    }
    if (fallas.length) console.error("[portal]", fallas.join(" · "));
    return fallas.length ? "falla" : "ok";
  } catch (e) {
    console.error("[portal]", e instanceof Error ? e.message : String(e));
    return "falla";
  }
}

// Al abrir una página, una vez enviada la respuesta: nadie espera al portal.
export function sincronizarPortalDespues() {
  after(() => sincronizarPortal(false));
}
