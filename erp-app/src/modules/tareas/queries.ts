import { createClient } from "@/lib/supabase/server";
import type { Tarea, TareaConRelaciones, TareaHilo, TareaNota, TareaPlantilla } from "./types";

const SELECT_HILO = "id, titulo, estado, creado_por, activo, created_at";

const SELECT_TAREA_CON_RELACIONES = `
  id, hilo_id, titulo, descripcion, asignado_a, creado_por, estado, fecha_vencimiento, activo, created_at,
  asignado:usuarios!tareas_asignado_a_fkey(nombre),
  creador:usuarios!tareas_creado_por_fkey(nombre),
  hilo:tareas_hilos(titulo)
`;

type TareaRow = Tarea & {
  asignado: { nombre: string } | null;
  creador: { nombre: string } | null;
  hilo: { titulo: string } | null;
};

function mapTareaConRelaciones(row: TareaRow): TareaConRelaciones {
  return {
    id: row.id,
    hilo_id: row.hilo_id,
    titulo: row.titulo,
    descripcion: row.descripcion,
    asignado_a: row.asignado_a,
    creado_por: row.creado_por,
    estado: row.estado,
    fecha_vencimiento: row.fecha_vencimiento,
    activo: row.activo,
    created_at: row.created_at,
    asignado_a_nombre: row.asignado?.nombre ?? "",
    creado_por_nombre: row.creador?.nombre ?? "",
    hilo_titulo: row.hilo?.titulo ?? null,
  };
}

async function getUserId(supabase: Awaited<ReturnType<typeof createClient>>) {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}

async function getTareasFiltradas({
  soloPropias,
  completadas,
}: {
  soloPropias: boolean;
  completadas: boolean;
}): Promise<TareaConRelaciones[]> {
  const supabase = await createClient();

  let query = supabase.from("tareas").select(SELECT_TAREA_CON_RELACIONES).eq("activo", true);
  query = completadas ? query.eq("estado", "completada") : query.neq("estado", "completada");

  if (soloPropias) {
    const userId = await getUserId(supabase);
    if (!userId) return [];
    query = query.or(`asignado_a.eq.${userId},creado_por.eq.${userId}`);
  }

  const { data, error } = await query.order("created_at", { ascending: false });
  if (error) throw error;
  return (data as unknown as TareaRow[]).map(mapTareaConRelaciones);
}

export const getMisTareasAbiertas = () => getTareasFiltradas({ soloPropias: true, completadas: false });
export const getMisTareasCompletadas = () => getTareasFiltradas({ soloPropias: true, completadas: true });
export const getTodasLasTareasAbiertas = () => getTareasFiltradas({ soloPropias: false, completadas: false });
export const getTodasLasTareasCompletadas = () => getTareasFiltradas({ soloPropias: false, completadas: true });

async function getTareasCompletadasCount(soloPropias: boolean): Promise<number> {
  const supabase = await createClient();
  let query = supabase
    .from("tareas")
    .select("id", { count: "exact", head: true })
    .eq("activo", true)
    .eq("estado", "completada");

  if (soloPropias) {
    const userId = await getUserId(supabase);
    if (!userId) return 0;
    query = query.or(`asignado_a.eq.${userId},creado_por.eq.${userId}`);
  }

  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

export const getMisTareasCompletadasCount = () => getTareasCompletadasCount(true);
export const getTodasLasTareasCompletadasCount = () => getTareasCompletadasCount(false);

export async function getHilosDisponibles(): Promise<TareaHilo[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_hilos")
    .select(SELECT_HILO)
    .eq("activo", true)
    .order("titulo");

  if (error) throw error;
  return data;
}

async function getNotasDeTareas(
  supabase: Awaited<ReturnType<typeof createClient>>,
  tareaIds: string[]
): Promise<TareaNota[]> {
  if (tareaIds.length === 0) return [];

  const { data, error } = await supabase
    .from("tareas_notas")
    .select("id, tarea_id, usuario_id, nota, created_at, usuario:usuarios(nombre)")
    .in("tarea_id", tareaIds)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data as unknown as (TareaNota & { usuario: { nombre: string } | null })[]).map((n) => ({
    id: n.id,
    tarea_id: n.tarea_id,
    usuario_id: n.usuario_id,
    usuario_nombre: n.usuario?.nombre ?? "",
    nota: n.nota,
    created_at: n.created_at,
  }));
}

export async function getHistorialHilo(hiloId: string): Promise<{
  hilo: TareaHilo | null;
  tareas: TareaConRelaciones[];
  notas: TareaNota[];
}> {
  const supabase = await createClient();

  const [{ data: hilo, error: hiloError }, { data: tareasData, error: tareasError }] = await Promise.all([
    supabase.from("tareas_hilos").select(SELECT_HILO).eq("id", hiloId).maybeSingle(),
    supabase
      .from("tareas")
      .select(SELECT_TAREA_CON_RELACIONES)
      .eq("hilo_id", hiloId)
      .eq("activo", true)
      .order("created_at", { ascending: false }),
  ]);

  if (hiloError) throw hiloError;
  if (tareasError) throw tareasError;

  const tareas = (tareasData as unknown as TareaRow[]).map(mapTareaConRelaciones);
  const notas = await getNotasDeTareas(supabase, tareas.map((t) => t.id));

  return { hilo, tareas, notas };
}

export async function getNotasDeTarea(tareaId: string): Promise<TareaNota[]> {
  const supabase = await createClient();
  return getNotasDeTareas(supabase, [tareaId]);
}

export async function getUsuariosParaAsignar(): Promise<{ id: string; nombre: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("usuarios")
    .select("id, nombre")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data;
}

export async function getPlantillas(): Promise<TareaPlantilla[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_plantillas")
    .select("id, nombre, creado_por, activo, created_at, items:tareas_plantillas_items(id, plantilla_id, titulo, descripcion, orden, activo)")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data.map((p) => ({
    ...p,
    items: p.items.filter((i) => i.activo).sort((a, b) => a.orden - b.orden),
  }));
}
