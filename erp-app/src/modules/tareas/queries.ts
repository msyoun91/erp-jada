import { createClient } from "@/lib/supabase/server";
import { REFERENCIA } from "./derivados";
import type { Asignable, Edicion, Hilo, Nota, Plantilla, PlantillaPaso, Tarea } from "./types";

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

export type PasoResumen = Pick<Tarea, "id" | "estado" | "asignado_id" | "asignado_equipo_id" | "vence" | "activo">;
export type HiloResumen = Hilo & { tareas: PasoResumen[] };

const RESUMEN = "*, tareas(id, estado, asignado_id, asignado_equipo_id, vence, activo)";

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
  enlaces: Record<string, string>;
};

// `ente:id` → ficha, de las referencias que quien lee puede abrir: el ente
// visible (RLS de `entes`) y `etiqueta_registro` no NULL. El resto queda en texto.
async function getEnlaces(textos: (string | null)[]): Promise<Record<string, string>> {
  const refs = new Set(textos.flatMap((t) => [...(t ?? "").matchAll(REFERENCIA)].map((m) => `${m[1]}:${m[2]}`)));
  if (refs.size === 0) return {};
  const supabase = await createClient();
  const { data: entes, error } = await supabase.from("entes").select("codigo, ruta");
  if (error) throw error;
  const rutas = new Map(entes.map((e) => [e.codigo, e.ruta]));
  const pares = await Promise.all(
    [...refs].map(async (ref) => {
      const [ente, id] = ref.split(":");
      const ruta = rutas.get(ente);
      if (!ruta) return null;
      const { data, error } = await supabase.rpc("etiqueta_registro", { p_ente: ente, p_id: id });
      if (error) throw error;
      return data === null ? null : ([ref, ruta.replace("{id}", id)] as const);
    })
  );
  return Object.fromEntries(pares.filter((p) => p !== null));
}

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
  const enlaces = await getEnlaces((pasos.data ?? []).map((p) => p.descripcion));
  return { hilo: hilo.data, pasos: pasos.data ?? [], notas: notas.data ?? [], ediciones: ediciones.data ?? [], enlaces };
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
export async function getMision(
  yo: string
): Promise<{ pasos: PasoMision[]; cadena: PasoCadena[]; enlaces: Record<string, string> }> {
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
  const [cadena, enlaces] = await Promise.all([getCadena(pasos), getEnlaces(pasos.map((p) => p.descripcion))]);
  return { pasos, cadena, enlaces };
}

async function getCadena(pasos: { hilo_id: string }[]): Promise<PasoCadena[]> {
  if (pasos.length === 0) return [];
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas")
    .select("id, paso_anterior_id, estado, created_at, titulo")
    .in("hilo_id", [...new Set(pasos.map((p) => p.hilo_id))])
    .eq("activo", true);
  if (error) throw error;
  return data;
}

export type PasoEquipo = Tarea & { tareas_hilos: Pick<Hilo, "titulo" | "responsable_id"> };

// Equipo: la bandeja del delegador. Pasos vivos de su equipo por decidir o por
// repartir, y los hilos donde participa el equipo (`equipo_id` guardado del
// hilo o de algún paso, como en la RLS).
export async function getEquipo(
  equipo: string
): Promise<{ pasos: PasoEquipo[]; cadena: PasoCadena[]; hilos: HiloResumen[] }> {
  const supabase = await createClient();
  const [pasos, delEquipo] = await Promise.all([
    supabase
      .from("tareas")
      .select("*, tareas_hilos!inner(titulo, responsable_id)")
      .eq("equipo_id", equipo)
      .eq("activo", true)
      .in("estado", ["solicitada", "pendiente"])
      .eq("tareas_hilos.activo", true)
      .eq("tareas_hilos.estado", "abierto"),
    supabase.from("tareas").select("hilo_id").eq("equipo_id", equipo).eq("activo", true),
  ]);
  if (pasos.error) throw pasos.error;
  if (delEquipo.error) throw delEquipo.error;

  const ids = [...new Set(delEquipo.data.map((t) => t.hilo_id))];
  const filtro = ids.length > 0 ? `equipo_id.eq.${equipo},id.in.(${ids.join(",")})` : `equipo_id.eq.${equipo}`;
  const { data: hilos, error } = await supabase
    .from("tareas_hilos")
    .select(RESUMEN)
    .eq("activo", true)
    .or(filtro)
    .order("updated_at", { ascending: false });
  if (error) throw error;

  return { pasos: pasos.data, cadena: await getCadena(pasos.data), hilos };
}

// Todas: lo que la RLS deja ver al admin, desactivados incluidos.
export async function getTodas(): Promise<HiloResumen[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("tareas_hilos").select(RESUMEN).order("updated_at", { ascending: false });
  if (error) throw error;
  return data;
}

export type PlantillaCompleta = Plantilla & { tareas_plantillas_pasos: PlantillaPaso[] };

// Las mías (también desactivadas), las publicadas y, al admin, todas: la RLS
// recorta. Cada vista filtra.
export async function getPlantillas(): Promise<PlantillaCompleta[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_plantillas")
    .select("*, tareas_plantillas_pasos(*)")
    .eq("tareas_plantillas_pasos.activo", true)
    .order("nombre")
    .order("orden", { referencedTable: "tareas_plantillas_pasos" });
  if (error) throw error;
  return data;
}
