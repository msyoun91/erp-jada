import type { ReactNode } from "react";
import { fichaObra } from "./obras/[id]/ficha";
import { fichaPersona } from "./contactos/personas/[id]/ficha";
import { fichaEmpresa } from "./contactos/empresas/[id]/ficha";
import { fichaHilo, fichaTarea } from "./tareas/[id]/ficha";

// El link de acción de Tareas: abre la ficha con ese panel.
export type AccionFicha = { vincular: string | null; estado: string | null };

const SIN_ACCION: AccionFicha = { vincular: null, estado: null };

export function accionDe(params: Record<string, string | string[] | undefined>): AccionFicha {
  const { vincular, estado } = params;
  return { vincular: typeof vincular === "string" ? vincular : null, estado: typeof estado === "string" ? estado : null };
}

// Ente → ficha, para verla al lado en Tareas. `hilo`: el que se está mirando,
// que la ficha no lista. `hilo` y `tarea`, compactas y sin acción (registro.md).
const FICHAS: Record<string, (id: string, accion: AccionFicha, hilo: string | null) => Promise<ReactNode | null>> = {
  obra: fichaObra,
  persona: fichaPersona,
  empresa: fichaEmpresa,
  hilo: (id) => fichaHilo(id),
  tarea: fichaTarea,
};

export async function ficha(
  ente: string,
  id: string,
  hilo: string | null = null,
  accion: AccionFicha = SIN_ACCION
): Promise<ReactNode | null> {
  return FICHAS[ente] ? FICHAS[ente](id, accion, hilo) : null;
}
