import { createClient } from "@/lib/supabase/server";
import { diaISO, hoyISO, sumarDias } from "@/lib/utils";
import {
  TAREAS_PAGE_SIZE,
  type DiaAuditoria,
  type EstadoTarea,
  type FiltrosAuditoria,
  type FiltrosTareas,
  type ModoTareas,
  type Tarea,
  type TareaConRelaciones,
  type TareaEvento,
  type TareaHilo,
  type TareaNota,
  type TareaPlantilla,
} from "./types";

const SELECT_HILO =
  "id, titulo, descripcion, estado, creado_por, activo, created_at, recurrencia_activa, recurrencia_una_vez, recurrencia_intervalo, recurrencia_cada, recurrencia_proxima, posponer_hasta";

const SELECT_TAREA_CON_RELACIONES = `
  id, hilo_id, titulo, descripcion, asignado_a, creado_por, estado, fecha_vencimiento, activo, created_at, updated_at,
  recurrencia_activa, recurrencia_una_vez, recurrencia_intervalo, recurrencia_cada, recurrencia_proxima, posponer_hasta,
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
    updated_at: row.updated_at,
    recurrencia_activa: row.recurrencia_activa,
    recurrencia_una_vez: row.recurrencia_una_vez,
    recurrencia_intervalo: row.recurrencia_intervalo,
    recurrencia_cada: row.recurrencia_cada,
    recurrencia_proxima: row.recurrencia_proxima,
    posponer_hasta: row.posponer_hasta,
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

// PostgREST parsea `or=(...)` con comas y paréntesis: si el texto del usuario
// los trae, rompe la query. Se van, no se escapan — son ruido en una búsqueda.
function textoBusqueda(texto: string | undefined): string {
  return (texto ?? "").replace(/[,()"\\%*]/g, " ").trim();
}

async function getTareasFiltradas({
  soloPropias,
  modo,
  page,
  filtros,
}: {
  soloPropias: boolean;
  modo: ModoTareas;
  page: number;
  filtros?: FiltrosTareas;
}): Promise<{ tareas: TareaConRelaciones[]; total: number }> {
  const supabase = await createClient();

  let query = supabase.from("tareas").select(SELECT_TAREA_CON_RELACIONES, { count: "exact" }).eq("activo", true);

  if (modo === "completadas") {
    query = query.eq("estado", "completada");
  } else {
    query = query.neq("estado", "completada");
    query =
      modo === "abiertas"
        ? query.or(`posponer_hasta.is.null,posponer_hasta.lte.${hoyISO()}`)
        : query.gt("posponer_hasta", hoyISO());
  }

  if (soloPropias) {
    const userId = await getUserId(supabase);
    if (!userId) return { tareas: [], total: 0 };
    query = query.or(`asignado_a.eq.${userId},creado_por.eq.${userId}`);
  }

  if (filtros?.asignado_a) query = query.eq("asignado_a", filtros.asignado_a);

  const texto = textoBusqueda(filtros?.texto);
  if (texto) query = query.or(`titulo.ilike.%${texto}%,descripcion.ilike.%${texto}%`);

  const from = page * TAREAS_PAGE_SIZE;
  // Completadas: lo último cerrado arriba. El instante exacto del cierre solo
  // vive en `tareas_eventos`, que exige `tareas_auditoria` — `updated_at` es la
  // aproximación que cualquier usuario puede leer (la mueve cualquier edición).
  const orderBy = modo === "pospuestas" ? "posponer_hasta" : modo === "completadas" ? "updated_at" : "created_at";
  const ascending = modo === "pospuestas";

  const { data, error, count } = await query
    .order(orderBy, { ascending })
    .range(from, from + TAREAS_PAGE_SIZE - 1);

  if (error) throw error;
  return { tareas: (data as unknown as TareaRow[]).map(mapTareaConRelaciones), total: count ?? 0 };
}

export const getMisTareasAbiertas = (page = 0, filtros?: FiltrosTareas) =>
  getTareasFiltradas({ soloPropias: true, modo: "abiertas", page, filtros });
export const getMisTareasCompletadas = (page = 0, filtros?: FiltrosTareas) =>
  getTareasFiltradas({ soloPropias: true, modo: "completadas", page, filtros });
export const getMisTareasPospuestas = (page = 0, filtros?: FiltrosTareas) =>
  getTareasFiltradas({ soloPropias: true, modo: "pospuestas", page, filtros });

export const getTodasLasTareasAbiertas = (page = 0, filtros?: FiltrosTareas) =>
  getTareasFiltradas({ soloPropias: false, modo: "abiertas", page, filtros });
export const getTodasLasTareasCompletadas = (page = 0, filtros?: FiltrosTareas) =>
  getTareasFiltradas({ soloPropias: false, modo: "completadas", page, filtros });
export const getTodasLasTareasPospuestas = (page = 0, filtros?: FiltrosTareas) =>
  getTareasFiltradas({ soloPropias: false, modo: "pospuestas", page, filtros });

async function getTareasCount(soloPropias: boolean, modo: Exclude<ModoTareas, "abiertas">): Promise<number> {
  const supabase = await createClient();
  let query = supabase.from("tareas").select("id", { count: "exact", head: true }).eq("activo", true);

  query =
    modo === "completadas" ? query.eq("estado", "completada") : query.neq("estado", "completada").gt("posponer_hasta", hoyISO());

  if (soloPropias) {
    const userId = await getUserId(supabase);
    if (!userId) return 0;
    query = query.or(`asignado_a.eq.${userId},creado_por.eq.${userId}`);
  }

  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

export const getMisTareasCompletadasCount = () => getTareasCount(true, "completadas");
export const getTodasLasTareasCompletadasCount = () => getTareasCount(false, "completadas");
export const getMisTareasPospuestasCount = () => getTareasCount(true, "pospuestas");
export const getTodasLasTareasPospuestasCount = () => getTareasCount(false, "pospuestas");

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

type EventoRow = {
  id: string;
  tarea_id: string;
  estado_anterior: EstadoTarea | null;
  estado_nuevo: EstadoTarea;
  created_at: string;
  tarea: { titulo: string; hilo: { titulo: string } | null } | null;
  usuario: { nombre: string } | null;
};

// Argentina no usa horario de verano desde 2009, así que el offset fijo -03:00
// alcanza para convertir el día elegido en el filtro al instante que guarda
// `created_at` (timestamptz). PostgREST no puede hacer `AT TIME ZONE` en un
// filtro; hacerlo con una función RPC sería más maquinaria por el mismo
// resultado mientras el offset no cambie.
function inicioDelDiaAR(dia: string): string {
  return `${dia}T00:00:00-03:00`;
}

export async function getAuditoria(
  filtros: FiltrosAuditoria,
  page = 0
): Promise<{ dias: DiaAuditoria[]; total: number }> {
  const supabase = await createClient();

  let query = supabase
    .from("tareas_eventos")
    .select(
      "id, tarea_id, estado_anterior, estado_nuevo, created_at, tarea:tareas(titulo, hilo:tareas_hilos(titulo)), usuario:usuarios(nombre)",
      { count: "exact" }
    )
    .eq("estado_nuevo", "completada");

  if (filtros.usuario_id) query = query.eq("usuario_id", filtros.usuario_id);
  if (filtros.desde) query = query.gte("created_at", inicioDelDiaAR(filtros.desde));
  if (filtros.hasta) query = query.lt("created_at", inicioDelDiaAR(sumarDias(filtros.hasta, 1)));

  const from = page * TAREAS_PAGE_SIZE;
  const { data, error, count } = await query
    .order("created_at", { ascending: false })
    .range(from, from + TAREAS_PAGE_SIZE - 1);

  if (error) throw error;

  const dias: DiaAuditoria[] = [];
  for (const row of data as unknown as EventoRow[]) {
    const dia = diaISO(new Date(row.created_at));
    const evento: TareaEvento = {
      id: row.id,
      tarea_id: row.tarea_id,
      tarea_titulo: row.tarea?.titulo ?? "",
      hilo_titulo: row.tarea?.hilo?.titulo ?? null,
      usuario_nombre: row.usuario?.nombre ?? null,
      estado_anterior: row.estado_anterior,
      estado_nuevo: row.estado_nuevo,
      created_at: row.created_at,
    };
    const ultimo = dias.at(-1);
    if (ultimo?.dia === dia) ultimo.eventos.push(evento);
    else dias.push({ dia, eventos: [evento] });
  }

  return { dias, total: count ?? 0 };
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
