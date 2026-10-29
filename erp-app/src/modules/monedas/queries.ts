import type { Moneda } from "@/lib/monedas";
import { createClient } from "@/lib/supabase/server";
import type { Aviso, FilaHistorial, TipoCambioHoy } from "./types";

// Las dos de la barra de menú devuelven vacío en vez de tirar, como la campanita
// (`notificaciones/queries.ts`): se renderizan desde el layout, y un error acá
// rompería todas las pantallas.
export async function getTiposCambioHoy(): Promise<TipoCambioHoy[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("monedas_hoy");
  if (error) return [];
  return (data ?? []) as TipoCambioHoy[];
}

// Vacío para quien no tiene `monedas_corregir`: lo filtra la base.
export async function getAvisos(): Promise<Aviso[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("monedas_avisos");
  if (error) return [];
  return (data ?? []) as Aviso[];
}

export async function getHistorial(moneda: Moneda): Promise<FilaHistorial[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("monedas_historial", { p_moneda: moneda, p_limite: 30 });
  if (error) throw error;
  return (data ?? []) as FilaHistorial[];
}

export async function getPrincipal(): Promise<Moneda> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("monedas_principal_actual");
  if (error) throw error;
  return data;
}
