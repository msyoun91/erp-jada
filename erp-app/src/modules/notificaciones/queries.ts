import { createClient } from "@/lib/supabase/server";
import type { Avisos, Notificacion } from "./types";

const SIN_AVISOS: Avisos = { vencidas: 0, vencen_hoy: 0 };

// Las dos devuelven vacío en vez de tirar, a diferencia del resto de las
// queries del repo: la campanita se renderiza desde el layout, así que un error
// acá no rompería una pantalla sino todas. Sin notificaciones el ERP funciona.

export async function getNotificaciones(): Promise<Notificacion[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("notificaciones_listar", { p_limite: 30 });
  if (error) return [];
  return data ?? [];
}

export async function getAvisos(): Promise<Avisos> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("notificaciones_avisos");
  if (error) return SIN_AVISOS;
  return data?.[0] ?? SIN_AVISOS;
}
