import { createClient } from "@/lib/supabase/server";
import { sumarDiasISO } from "@/lib/utils";
import type {
  EventoAuditoria,
  TareaConAsignados,
  TareaHilo,
  TareaPendiente,
  TareaPlantilla,
  TareaPlantillaItem,
  TareaProyecto,
  Usuario,
} from "./types";

function inicioDiaAR(fechaISO: string) {
  // Argentina no usa horario de verano desde 2009 — offset fijo -03:00.
  return `${fechaISO}T03:00:00.000Z`;
}

export async function getUsuarioActualId(): Promise<string | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}

export async function getUsuariosParaAsignar(): Promise<Usuario[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("usuarios")
    .select("id, nombre")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data;
}

// Lista unificada de la vista "Lista": hilos + tareas sueltas visibles para
// el usuario actual (RLS ya filtra por cascada — acá no se re-implementa
// visibilidad). Reactiva posponer vencidos antes de leer (sin cron).
export async function getListaTareas(): Promise<{ hilos: TareaHilo[]; tareas: TareaConAsignados[] }> {
  const supabase = await createClient();
  await supabase.rpc("reactivar_posponer_vencidos");

  const [{ data: hilos, error: errorHilos }, { data: tareas, error: errorTareas }] = await Promise.all([
    supabase
      .from("tareas_hilos")
      .select("*")
      .eq("activo", true)
      .order("created_at", { ascending: false }),
    supabase
      .from("tareas")
      .select(
        "*, tareas_asignados(usuario_id, activo, usuarios(nombre)), tareas_notas(id, tarea_id, usuario_id, nota, activo, created_at, usuarios(nombre))",
      )
      .eq("activo", true)
      .order("created_at", { ascending: false }),
  ]);

  if (errorHilos) throw errorHilos;
  if (errorTareas) throw errorTareas;

  // activo/orden de las notas se resuelven acá y no en la query: filtrar un
  // embed en PostgREST lo vuelve inner join y perderíamos las tareas sin notas.
  const conNotas = (tareas ?? []).map((t) => ({
    ...t,
    tareas_notas: t.tareas_notas
      .filter((n) => n.activo)
      .sort((a, b) => b.created_at.localeCompare(a.created_at)),
  }));

  return { hilos: hilos ?? [], tareas: conNotas };
}

export async function getHiloTareas(hiloId: string): Promise<TareaConAsignados[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas")
    .select("*, tareas_asignados(usuario_id, activo, usuarios(nombre))")
    .eq("hilo_id", hiloId)
    .eq("activo", true)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data ?? [];
}

export async function getProyectos(): Promise<TareaProyecto[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_proyectos")
    .select("*")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data ?? [];
}

// Mapa proyecto -> ids de miembros activos, en una sola query para todos los
// proyectos que el usuario ve (RLS ya filtra): el picker de asignados lo
// necesita en cada vista, y pedirlo por proyecto eran N requests.
export async function getMiembrosPorProyecto(): Promise<Record<string, string[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_proyectos_miembros")
    .select("proyecto_id, usuario_id")
    .eq("activo", true);

  if (error) throw error;

  const mapa: Record<string, string[]> = {};
  for (const m of data ?? []) {
    (mapa[m.proyecto_id] ??= []).push(m.usuario_id);
  }
  return mapa;
}

export async function getPlantillas(): Promise<TareaPlantilla[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_plantillas")
    .select("*")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;
  return data ?? [];
}

export async function getPlantillaItems(plantillaId: string): Promise<TareaPlantillaItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_plantillas_items")
    .select("*")
    .eq("plantilla_id", plantillaId)
    .eq("activo", true)
    .order("orden");

  if (error) throw error;
  return data ?? [];
}

// Auditoría: solo cambios a 'completada' — "qué se realizó", no cada
// transición de estado (el trigger loguea todas, la vista filtra acá).
// fecha_asignacion se resuelve aparte: no hay FK directa entre
// tareas_eventos y tareas_asignados, así que se arma un mapa
// (tarea_id, usuario_id) -> primera vez que ese usuario quedó asignado
// (incluye filas inactivas — reasignado no debe perder el dato histórico).
export async function getAuditoria(
  desde: string,
  hasta: string,
  usuarioId?: string
): Promise<EventoAuditoria[]> {
  const supabase = await createClient();
  let query = supabase
    .from("tareas_eventos")
    .select("id, tarea_id, usuario_id, created_at, tareas(titulo, created_at), usuarios(nombre)")
    .eq("estado_nuevo", "completada")
    .gte("created_at", inicioDiaAR(desde))
    .lt("created_at", inicioDiaAR(sumarDiasISO(hasta, 1)))
    .order("created_at", { ascending: false });

  if (usuarioId) {
    query = query.eq("usuario_id", usuarioId);
  }

  const { data, error } = await query;
  if (error) throw error;
  const eventos = data ?? [];
  if (eventos.length === 0) return [];

  const tareaIds = [...new Set(eventos.map((e) => e.tarea_id))];
  const { data: asignaciones, error: errorAsignaciones } = await supabase
    .from("tareas_asignados")
    .select("tarea_id, usuario_id, created_at")
    .in("tarea_id", tareaIds);

  if (errorAsignaciones) throw errorAsignaciones;

  const fechaAsignacion = new Map<string, string>();
  for (const a of asignaciones ?? []) {
    const key = `${a.tarea_id}:${a.usuario_id}`;
    const actual = fechaAsignacion.get(key);
    if (!actual || a.created_at < actual) fechaAsignacion.set(key, a.created_at);
  }

  return eventos.map((e) => ({
    ...e,
    fecha_asignacion: e.usuario_id ? (fechaAsignacion.get(`${e.tarea_id}:${e.usuario_id}`) ?? null) : null,
  }));
}

// §9 spec: panorama de lo que un usuario todavía tiene incompleto — para que
// el manager vea, junto a lo completado del día, qué le queda pendiente.
export async function getPendientesUsuario(usuarioId: string): Promise<TareaPendiente[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas")
    .select("id, titulo, estado, fecha_vencimiento, tareas_hilos(titulo), tareas_asignados!inner(usuario_id, activo)")
    .eq("activo", true)
    .in("estado", ["pendiente", "en_progreso"])
    .eq("tareas_asignados.usuario_id", usuarioId)
    .eq("tareas_asignados.activo", true)
    .order("fecha_vencimiento", { ascending: true, nullsFirst: false });

  if (error) throw error;
  return (data ?? []).map((t) => ({
    id: t.id,
    titulo: t.titulo,
    estado: t.estado,
    fecha_vencimiento: t.fecha_vencimiento,
    hilo_titulo: t.tareas_hilos?.titulo ?? null,
  }));
}
