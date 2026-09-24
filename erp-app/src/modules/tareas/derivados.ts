import type { EstadoTarea, PrioridadTarea } from "./types";

type PasoCadena = {
  id: string;
  paso_anterior_id: string | null;
  estado: EstadoTarea;
  created_at: string;
};

export const ESTADOS_ABIERTOS: EstadoTarea[] = ["solicitada", "pendiente", "rechazada"];

export function estaAbierto(estado: EstadoTarea) {
  return ESTADOS_ABIERTOS.includes(estado);
}

// Espeja `tareas_bloquea` (sql/113), que es quien decide: el primer previo no
// cancelado, subiendo la cadena, sin completar. Un cancelado es transparente.
export function estaBloqueado<T extends PasoCadena>(paso: T, porId: Map<string, T>): boolean {
  if (!estaAbierto(paso.estado)) return false;
  const vistos = new Set<string>();
  let previo = paso.paso_anterior_id ? porId.get(paso.paso_anterior_id) : undefined;
  while (previo && previo.estado === "cancelada" && !vistos.has(previo.id)) {
    vistos.add(previo.id);
    previo = previo.paso_anterior_id ? porId.get(previo.paso_anterior_id) : undefined;
  }
  return previo !== undefined && previo.estado !== "completada";
}

// Cada cadena contigua, de la raíz a la cola; las raíces por orden de alta.
// Un paso cuyo previo no está en la lista (desactivado) arranca su propia
// cadena en vez de perderse.
export function ordenarPasos<T extends PasoCadena>(pasos: T[]): T[] {
  const ids = new Set(pasos.map((p) => p.id));
  const siguiente = new Map<string, T>();
  for (const p of pasos) if (p.paso_anterior_id && ids.has(p.paso_anterior_id)) siguiente.set(p.paso_anterior_id, p);

  const raices = pasos
    .filter((p) => !p.paso_anterior_id || !ids.has(p.paso_anterior_id))
    .sort((a, b) => a.created_at.localeCompare(b.created_at));

  const salida: T[] = [];
  const vistos = new Set<string>();
  for (const raiz of raices) {
    for (let p: T | undefined = raiz; p && !vistos.has(p.id); p = siguiente.get(p.id)) {
      vistos.add(p.id);
      salida.push(p);
    }
  }
  return salida;
}

export function estaEnEspera(paso: { estado: EstadoTarea; espera_hasta: string | null }, hoy: string) {
  return paso.estado === "pendiente" && paso.espera_hasta !== null && paso.espera_hasta > hoy;
}

export function estaVencido(paso: { estado: EstadoTarea; vence: string | null }, hoy: string) {
  return estaAbierto(paso.estado) && paso.vence !== null && paso.vence < hoy;
}

type PasoOrden = { prioridad: PrioridadTarea; vence: string | null; created_at: string };
const RANGO_PRIORIDAD: Record<PrioridadTarea, number> = { alta: 0, media: 1, baja: 2 };

// Orden de Misión: prioridad, después lo que vence antes (sin fecha al final),
// después lo más viejo.
export function compararMision(a: PasoOrden, b: PasoOrden) {
  return (
    RANGO_PRIORIDAD[a.prioridad] - RANGO_PRIORIDAD[b.prioridad] ||
    (a.vence ?? "9999").localeCompare(b.vence ?? "9999") ||
    a.created_at.localeCompare(b.created_at)
  );
}

type Recibible = { usuario_id: string | null; equipo_id: string | null; pedido: boolean; puede_recibir: boolean };

function buscar<T extends Recibible>(asignables: T[], id: string | null) {
  return id ? asignables.find((a) => a.usuario_id === id || a.equipo_id === id) : undefined;
}

// Espeja `tareas_puede_recibir` a través de `tareas_asignables()`: quien no
// figura está inactivo.
export function puedeRecibir(asignables: Recibible[], id: string | null) {
  return buscar(asignables, id)?.puede_recibir === true;
}

// Huérfano (Todas): abierto, con responsable o asignado de un paso abierto
// que ya no puede recibir.
export function esHuerfano(
  hilo: { activo: boolean; estado: string; responsable_id: string; tareas: { activo: boolean; estado: EstadoTarea; asignado_id: string | null; asignado_equipo_id: string | null }[] },
  asignables: Recibible[]
) {
  if (!hilo.activo || hilo.estado !== "abierto") return false;
  if (!puedeRecibir(asignables, hilo.responsable_id)) return true;
  return hilo.tareas.some(
    (t) => t.activo && estaAbierto(t.estado) && !puedeRecibir(asignables, t.asignado_id ?? t.asignado_equipo_id)
  );
}

// "A revisar" de un paso de plantilla con asignado fijo: `usar_plantilla` lo
// cambiaría por quien la usa, o la base lo rechazaría como pedido (TA010).
export function motivoRevisar(
  paso: { asignado_id: string | null; asignado_equipo_id: string | null },
  asignables: Recibible[],
  pedir: boolean
): "no_recibe" | "pedido" | null {
  const id = paso.asignado_id ?? paso.asignado_equipo_id;
  if (!id) return null;
  const a = buscar(asignables, id);
  if (!a?.puede_recibir) return "no_recibe";
  if (a.pedido && !pedir) return "pedido";
  return null;
}

// `{ente:uuid|nombre}` (sql/119): grupos ente, id, nombre. Sin `|nombre` no es
// referencia y queda tal cual.
export const REFERENCIA = /\{([a-z_]+):([0-9a-f-]{36})\|([^}]*)\}/g;
