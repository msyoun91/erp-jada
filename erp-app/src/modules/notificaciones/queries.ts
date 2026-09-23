import { createClient } from "@/lib/supabase/server";
import type { Notificacion } from "./types";

// Devuelve vacío en vez de tirar, a diferencia del resto de las queries del
// repo: la campanita se renderiza desde el layout, así que un error acá no
// rompería una pantalla sino todas. Sin notificaciones el ERP funciona.
export async function getNotificaciones(): Promise<Notificacion[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("notificaciones_listar", { p_limite: 30 });
  if (error) return [];
  return (data ?? []) as Notificacion[];
}
