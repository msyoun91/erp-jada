import { createClient } from "@/lib/supabase/server";
import type { Equipo, Submodulo, Usuario } from "./types";

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
    .select("id, codigo, modulo, tipo, vista_id, nombre, orden, delegable")
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

export async function getEquipos(): Promise<Equipo[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("equipos")
    .select("id, nombre, activo")
    .order("nombre");

  if (error) throw error;
  return data;
}

// usuario_id → equipo_id de la membresía vigente.
export async function getMembresias(): Promise<Record<string, string>> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("equipos_miembros")
    .select("usuario_id, equipo_id")
    .eq("activo", true);

  if (error) throw error;
  return Object.fromEntries(data.map((m) => [m.usuario_id, m.equipo_id]));
}
