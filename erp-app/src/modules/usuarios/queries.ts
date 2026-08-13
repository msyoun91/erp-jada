import { createClient } from "@/lib/supabase/server";
import type { Submodulo, Usuario } from "./types";

export async function getUsuarios(): Promise<Usuario[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("usuarios")
    .select("id, nombre, email, activo, created_at")
    .order("nombre");

  if (error) throw error;
  return data;
}

export async function getSubmodulos(): Promise<Submodulo[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("submodulos")
    .select("id, codigo, modulo, tipo, vista_id, nombre, orden")
    .eq("activo", true)
    .order("modulo")
    .order("orden");

  if (error) throw error;
  return data;
}

export async function getAsignaciones(): Promise<Record<string, string[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("usuario_submodulos")
    .select("usuario_id, submodulo_id")
    .eq("activo", true);

  if (error) throw error;

  const asignaciones: Record<string, string[]> = {};
  for (const row of data) {
    (asignaciones[row.usuario_id] ??= []).push(row.submodulo_id);
  }
  return asignaciones;
}
