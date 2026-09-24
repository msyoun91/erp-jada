import { createClient } from "@/lib/supabase/server";
import type { Equipo, MiEquipo, Otorgamiento, Submodulo, SubmoduloRegla, Usuario } from "./types";

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

export async function getSubmoduloReglas(): Promise<SubmoduloRegla[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("submodulo_reglas")
    .select("submodulo_id, otro_id, tipo")
    .eq("activo", true);

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

// Delegada = la otorgó un miembro de un equipo (`equipo_de`, sql/105): el admin
// nunca es miembro. usuario → submódulo → quien la delegó.
export async function getDelegadas(): Promise<Record<string, Record<string, string>>> {
  const supabase = await createClient();
  const [{ data, error }, membresias] = await Promise.all([
    supabase
      .from("usuario_submodulos")
      .select("usuario_id, submodulo_id, otorgada_por")
      .eq("activo", true)
      .not("otorgada_por", "is", null),
    getMembresias(),
  ]);

  if (error) throw error;

  const delegadas: Record<string, Record<string, string>> = {};
  for (const row of data) {
    if (row.otorgada_por && membresias[row.otorgada_por]) {
      (delegadas[row.usuario_id] ??= {})[row.submodulo_id] = row.otorgada_por;
    }
  }
  return delegadas;
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

// Con la sesión del delegador: la RLS ya recorta a su equipo (`sql/104`).
export async function getMiEquipo(): Promise<MiEquipo | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: propia, error: propiaError } = await supabase
    .from("equipos_miembros")
    .select("equipos(id, nombre, activo)")
    .eq("usuario_id", user.id)
    .eq("activo", true)
    .maybeSingle();

  if (propiaError) throw propiaError;
  if (!propia?.equipos) return null;
  const equipo = propia.equipos;

  const { data: filas, error: filasError } = await supabase
    .from("equipos_miembros")
    .select("usuarios(id, nombre, email, telefono, activo)")
    .eq("equipo_id", equipo.id)
    .eq("activo", true);

  if (filasError) throw filasError;
  const miembros = filas
    .map((f) => f.usuarios)
    .filter((u): u is NonNullable<typeof u> => u !== null)
    .sort((a, b) => a.nombre.localeCompare(b.nombre));

  const { data: asignadas, error: asignadasError } = await supabase
    .from("usuario_submodulos")
    .select("usuario_id, submodulo_id, otorgada_por")
    .in("usuario_id", miembros.map((m) => m.id))
    .eq("activo", true);

  if (asignadasError) throw asignadasError;
  const permisos: Record<string, Otorgamiento[]> = {};
  for (const { usuario_id, ...otorgamiento } of asignadas) {
    (permisos[usuario_id] ??= []).push(otorgamiento);
  }

  return { yo: user.id, equipo, miembros, permisos };
}
