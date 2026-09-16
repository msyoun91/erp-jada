import { createClient } from "@/lib/supabase/server";
import { getUsuarioActualId, getUsuariosActivos } from "@/lib/usuarios";
import { sumarDiasISO } from "@/lib/utils";
import { puedeAsignar, puedeGestionarAjenas } from "./permissions";
import type { TareasContexto } from "./components/tareasContexto";
import type {
  Ente,
  EventoAuditoria,
  PlantillaCompleta,
  RegistroElegido,
  TareaConAsignados,
  TareaHilo,
  TareaPendiente,
  TareaProyecto,
  Usuario,
  VinculoTarea,
} from "./types";

function inicioDiaAR(fechaISO: string) {
  // Argentina no usa horario de verano desde 2009 — offset fijo -03:00.
  return `${fechaISO}T03:00:00.000Z`;
}

export { getUsuarioActualId };

export function getUsuariosParaAsignar(): Promise<Usuario[]> {
  return getUsuariosActivos();
}

// Compartido por getListaTareas y getTareasDeRegistro: la misma forma de
// tarea en toda la UI del módulo (isla, panel, hilo).
const SELECT_TAREAS =
  "*, tareas_asignados(usuario_id, activo, usuarios(nombre)), tareas_notas(id, tarea_id, usuario_id, nota, activo, created_at, usuarios(nombre))";

type NotaCruda = { activo: boolean; created_at: string };

// activo/orden de las notas se resuelven acá y no en la query: filtrar un
// embed en PostgREST lo vuelve inner join y perderíamos las tareas sin notas.
// Genérica (no fijada a TareaConAsignados) para que el tipo real del select
// de cada llamada — que Supabase infiere distinto según el resto de la
// query — siga viajando intacto hasta el return final de cada función.
function conNotasYVinculos<T extends { id: string; tareas_notas: NotaCruda[] }>(
  tareas: T[],
  vinculos: VinculoTarea[],
): (T & { vinculos: VinculoTarea[] })[] {
  return tareas.map((t) => ({
    ...t,
    tareas_notas: t.tareas_notas.filter((n) => n.activo).sort((a, b) => b.created_at.localeCompare(a.created_at)),
    vinculos: vinculos.filter((v) => v.tarea_id === t.id),
  }));
}

// Lista unificada de la vista "Lista": hilos + tareas sueltas visibles para
// el usuario actual (RLS ya filtra por cascada — acá no se re-implementa
// visibilidad). Reactiva posponer vencidos antes de leer (sin cron).
export async function getListaTareas(): Promise<{ hilos: TareaHilo[]; tareas: TareaConAsignados[] }> {
  const supabase = await createClient();
  await supabase.rpc("reactivar_posponer_vencidos");

  const [
    { data: hilos, error: errorHilos },
    { data: tareas, error: errorTareas },
    { data: vinculos, error: errorVinculos },
  ] = await Promise.all([
    supabase
      .from("tareas_hilos")
      .select("*")
      .eq("activo", true)
      .order("created_at", { ascending: false }),
    supabase.from("tareas").select(SELECT_TAREAS).eq("activo", true).order("created_at", { ascending: false }),
    supabase.rpc("vinculos_de_tareas"),
  ]);

  if (errorHilos) throw errorHilos;
  if (errorTareas) throw errorTareas;
  if (errorVinculos) throw errorVinculos;

  return { hilos: hilos ?? [], tareas: conNotasYVinculos(tareas ?? [], vinculos ?? []) };
}

// Los seis valores que toda vista de Tareas necesita para montar
// TareasContextoProvider — idéntico en las cuatro pages del módulo (Lista,
// Misión, Proyectos, Plantillas) y en la sección Tareas de una ficha.
export async function getTareasContexto(): Promise<TareasContexto> {
  const [usuarios, proyectos, miembrosPorProyecto, usuarioActualId, gestionarAjenas, asignar] = await Promise.all([
    getUsuariosParaAsignar(),
    getProyectos(),
    getMiembrosPorProyecto(),
    getUsuarioActualId(),
    puedeGestionarAjenas(),
    puedeAsignar(),
  ]);
  return { usuarios, proyectos, miembrosPorProyecto, usuarioActualId, gestionarAjenas, puedeAsignar: asignar };
}

// Las tareas de la sección "Tareas" de una ficha de obra, empresa o persona:
// `tareas_de_registro` (RLS + `etiqueta_registro`) solo decide cuáles y en qué
// orden — se re-consulta con el select completo (asignados y notas) para que
// TareaCard reciba la misma forma que en la Lista. `delHilo` son las tareas
// activas de los hilos con algún paso acá, para que `cadenasDePasos` calcule
// posición y bloqueo igual que en la Lista; `hilos`, para el proyecto heredado.
export async function getTareasDeRegistro(
  ente: "obra" | "empresa" | "persona",
  registroId: string,
): Promise<{ tareas: TareaConAsignados[]; delHilo: TareaConAsignados[]; hilos: TareaHilo[] }> {
  const supabase = await createClient();
  await supabase.rpc("reactivar_posponer_vencidos");

  const { data: filas, error: errorFilas } = await supabase.rpc("tareas_de_registro", {
    p_ente: ente,
    p_registro_id: registroId,
  });
  if (errorFilas) throw errorFilas;

  const ids = (filas ?? []).map((f) => f.id);
  if (ids.length === 0) return { tareas: [], delHilo: [], hilos: [] };

  const [{ data: vinculos, error: errorVinculos }, { data: tareas, error: errorTareas }] = await Promise.all([
    supabase.rpc("vinculos_de_tareas"),
    supabase.from("tareas").select(SELECT_TAREAS).in("id", ids).eq("activo", true),
  ]);
  if (errorVinculos) throw errorVinculos;
  if (errorTareas) throw errorTareas;

  const conNotas = conNotasYVinculos(tareas ?? [], vinculos ?? []);
  const porId = new Map(conNotas.map((t) => [t.id, t]));
  // tareas_de_registro ya deja lo terminado al final — se respeta ese orden.
  const ordenadas: TareaConAsignados[] = [];
  for (const id of ids) {
    const t = porId.get(id);
    if (t) ordenadas.push(t);
  }

  const hiloIds = [...new Set(ordenadas.map((t) => t.hilo_id).filter((id): id is string => id !== null))];
  if (hiloIds.length === 0) return { tareas: ordenadas, delHilo: [], hilos: [] };

  const [{ data: delHilo, error: errorDelHilo }, { data: hilos, error: errorHilos }] = await Promise.all([
    supabase.from("tareas").select(SELECT_TAREAS).in("hilo_id", hiloIds).eq("activo", true),
    supabase.from("tareas_hilos").select("*").in("id", hiloIds),
  ]);
  if (errorDelHilo) throw errorDelHilo;
  if (errorHilos) throw errorHilos;

  return { tareas: ordenadas, delHilo: conNotasYVinculos(delHilo ?? [], vinculos ?? []), hilos: hilos ?? [] };
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

// Las plantillas visibles con sus hilos y pasos en una sola query (RLS ya
// recorta por alcance y por el submódulo del disparador). `activo` y el orden
// de los embeds se resuelven acá: guardar reemplaza los pasos, así que cada
// plantilla arrastra filas desactivadas de sus versiones anteriores. De las
// activaciones, la RLS solo devuelve la propia.
export async function getPlantillas(): Promise<PlantillaCompleta[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tareas_plantillas")
    .select("*, tareas_plantillas_hilos(*), tareas_plantillas_items(*), tareas_plantillas_activaciones(activo)")
    .eq("activo", true)
    .order("nombre");

  if (error) throw error;

  return (data ?? []).map(({ tareas_plantillas_hilos, tareas_plantillas_items, tareas_plantillas_activaciones, ...p }) => ({
    ...p,
    hilos: tareas_plantillas_hilos.filter((h) => h.activo).sort((a, b) => a.orden - b.orden),
    items: tareas_plantillas_items.filter((i) => i.activo).sort((a, b) => a.orden - b.orden),
    activada: tareas_plantillas_activaciones.some((a) => a.activo),
  }));
}

// Los entes que quien arma una plantilla puede usar de disparador: la RLS de
// `entes` deja solo los de submódulos que tiene.
export async function getEntes(): Promise<Ente[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("entes").select("codigo, datos, disparos").order("codigo");

  if (error) throw error;
  return data ?? [];
}

// Módulos para el toggle de "Relacionar": la RLS de `entes` ya deja solo los
// de submódulos que quien busca tiene.
export async function getModulosRelacionables(): Promise<string[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("entes").select("modulo").order("modulo");

  if (error) throw error;
  return [...new Set((data ?? []).map((e) => e.modulo))];
}

// El registro desde el que se pidió "Nueva tarea" (`/tareas?nueva=obra:{id}`),
// si quien llega lo puede abrir.
export async function getRegistro(ente: string, id: string): Promise<RegistroElegido | null> {
  const supabase = await createClient();
  const [{ data: etiqueta }, { data: e }] = await Promise.all([
    supabase.rpc("etiqueta_registro", { p_ente: ente, p_id: id }),
    supabase.from("entes").select("ruta").eq("codigo", ente).maybeSingle(),
  ]);
  if (!etiqueta || !e) return null;
  return { ente, registro_id: id, etiqueta, detalle: null, href: e.ruta.replace("{id}", id) };
}

// Auditoría: solo los pasos a 'completada' — "qué se realizó", no cada
// transición (`eventos` guarda todas, sql/068; la vista filtra acá).
// `eventos.registro_id` no tiene FK, así que la tarea no se embebe: título y
// creación salen de una segunda consulta, junto con fecha_asignacion
// (tarea_id, usuario_id) -> primera vez que ese usuario quedó asignado
// (incluye filas inactivas — reasignado no debe perder el dato histórico).
export async function getAuditoria(
  desde: string,
  hasta: string,
  usuarioId?: string
): Promise<EventoAuditoria[]> {
  const supabase = await createClient();
  let query = supabase
    .from("eventos")
    .select("id, registro_id, actor_id, created_at, usuarios(nombre)")
    .eq("ente", "tarea")
    .eq("evento", "estado")
    .eq("detalle->>estado", "completada")
    .gte("created_at", inicioDiaAR(desde))
    .lt("created_at", inicioDiaAR(sumarDiasISO(hasta, 1)))
    .order("created_at", { ascending: false });

  if (usuarioId) {
    query = query.eq("actor_id", usuarioId);
  }

  const { data, error } = await query;
  if (error) throw error;
  const eventos = data ?? [];
  if (eventos.length === 0) return [];

  const tareaIds = [...new Set(eventos.map((e) => e.registro_id))];
  const [{ data: tareas, error: errorTareas }, { data: asignaciones, error: errorAsignaciones }] = await Promise.all([
    supabase.from("tareas").select("id, titulo, created_at").in("id", tareaIds),
    supabase.from("tareas_asignados").select("tarea_id, usuario_id, created_at").in("tarea_id", tareaIds),
  ]);

  if (errorTareas) throw errorTareas;
  if (errorAsignaciones) throw errorAsignaciones;

  const tareaPorId = new Map((tareas ?? []).map((t) => [t.id, { titulo: t.titulo, created_at: t.created_at }]));
  const fechaAsignacion = new Map<string, string>();
  for (const a of asignaciones ?? []) {
    const key = `${a.tarea_id}:${a.usuario_id}`;
    const actual = fechaAsignacion.get(key);
    if (!actual || a.created_at < actual) fechaAsignacion.set(key, a.created_at);
  }

  return eventos.map((e) => ({
    id: e.id,
    tarea_id: e.registro_id,
    usuario_id: e.actor_id,
    created_at: e.created_at,
    tareas: tareaPorId.get(e.registro_id) ?? null,
    usuarios: e.usuarios,
    fecha_asignacion: e.actor_id ? (fechaAsignacion.get(`${e.registro_id}:${e.actor_id}`) ?? null) : null,
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

// Pasos del tutorial que el usuario ya vio. La RLS acota a sus propias filas,
// así que no hace falta filtrar por usuario acá.
export async function getTutorialVisto(): Promise<string[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("usuario_tutorial").select("paso");

  if (error) throw error;
  return (data ?? []).map((f) => f.paso);
}
