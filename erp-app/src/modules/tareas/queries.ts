import { createClient } from "@/lib/supabase/server";
import type { Asignable, Edicion, Hilo, Nota, Tarea } from "./types";

export type Contexto = {
  yo: string;
  miEquipo: string | null;
  // id de usuario o equipo → nombre, de lo que se ve (`tareas_nombres`).
  nombres: Record<string, string>;
};

export async function getContexto(): Promise<Contexto> {
  const supabase = await createClient();
  const [{ data: auth }, equipo, nombres] = await Promise.all([
    supabase.auth.getUser(),
    supabase.rpc("mi_equipo"),
    supabase.rpc("tareas_nombres"),
  ]);
  if (equipo.error) throw equipo.error;
  if (nombres.error) throw nombres.error;
  return {
    yo: auth.user?.id ?? "",
    miEquipo: equipo.data,
    nombres: Object.fromEntries(nombres.data.map((n) => [n.id, n.nombre])),
  };
}

export async function getAsignables(): Promise<Asignable[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("tareas_asignables");
  if (error) throw error;
  return data;
}

export type PasoResumen = Pick<Tarea, "id" | "estado" | "asignado_id" | "vence" | "activo">;
export type HiloResumen = Hilo & { tareas: PasoResumen[] };

const RESUMEN = "*, tareas(id, estado, asignado_id, vence, activo)";

// Hilos: donde participo como responsable o asignado de algún paso activo. La
// RLS deja ver más (el equipo del delegador, todo al admin); eso va en Equipo
// y en Todas.
export async function getMisHilos(yo: string): Promise<HiloResumen[]> {
  const supabase = await createClient();
  const { data: mios, error: miosError } = await supabase
    .from("tareas")
    .select("hilo_id")
    .eq("asignado_id", yo)
    .eq("activo", true);
  if (miosError) throw miosError;

  const ids = [...new Set(mios.map((t) => t.hilo_id))];
  const filtro = ids.length > 0 ? `responsable_id.eq.${yo},id.in.(${ids.join(",")})` : `responsable_id.eq.${yo}`;

  const { data, error } = await supabase
    .from("tareas_hilos")
    .select(RESUMEN)
    .eq("activo", true)
    .or(filtro)
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return data;
}

export type HiloCompleto = {
  hilo: Hilo;
  pasos: Tarea[];
  notas: Nota[];
  ediciones: Edicion[];
};

// Lo que no se ve lo recorta la RLS: sin hilo visible, null.
export async function getHilo(id: string): Promise<HiloCompleto | null> {
  const supabase = await createClient();
  const [hilo, pasos, notas, ediciones] = await Promise.all([
    supabase.from("tareas_hilos").select("*").eq("id", id).maybeSingle(),
    supabase.from("tareas").select("*").eq("hilo_id", id),
    supabase.from("tareas_notas").select("*").eq("hilo_id", id).order("created_at"),
    supabase.from("tareas_ediciones").select("*").eq("hilo_id", id).order("created_at"),
  ]);
  for (const r of [hilo, pasos, notas, ediciones]) if (r.error) throw r.error;
  if (!hilo.data) return null;
  return { hilo: hilo.data, pasos: pasos.data ?? [], notas: notas.data ?? [], ediciones: ediciones.data ?? [] };
}

export async function getHiloDePaso(id: string): Promise<string | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("tareas").select("hilo_id").eq("id", id).maybeSingle();
  if (error) throw error;
  return data?.hilo_id ?? null;
}

export type PasoCadena = Pick<Tarea, "id" | "paso_anterior_id" | "estado" | "created_at" | "titulo">;
export type PasoMision = Tarea & { tareas_hilos: Pick<Hilo, "titulo"> };

// Misión: mis pasos por decidir o por hacer, de hilos vivos. Lo asignado a mi
// equipo va en Equipo. `cadena` trae los pasos de esos hilos para derivar el
// bloqueo, como en el hilo.
export async function getMision(yo: string): Promise<{ pasos: PasoMision[]; cadena: PasoCadena[] }> {
  const supabase = await createClient();
  const { data: pasos, error } = await supabase
    .from("tareas")
    .select("*, tareas_hilos!inner(titulo)")
    .eq("asignado_id", yo)
    .eq("activo", true)
    .in("estado", ["solicitada", "pendiente"])
    .eq("tareas_hilos.activo", true)
    .eq("tareas_hilos.estado", "abierto");
  if (error) throw error;
  if (pasos.length === 0) return { pasos, cadena: [] };

  const { data: cadena, error: cadenaError } = await supabase
    .from("tareas")
    .select("id, paso_anterior_id, estado, created_at, titulo")
    .in("hilo_id", [...new Set(pasos.map((p) => p.hilo_id))])
    .eq("activo", true);
  if (cadenaError) throw cadenaError;
  return { pasos, cadena };
}
