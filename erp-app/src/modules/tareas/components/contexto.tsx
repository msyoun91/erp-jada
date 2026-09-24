"use client";

import { createContext, useContext } from "react";
import type { Asignable } from "../types";

export type TareasCtx = {
  yo: string;
  miEquipo: string | null;
  nombres: Record<string, string>;
  asignables: Asignable[];
  admin: boolean;
  pedir: boolean;
  // tareas_equipo: el delegador de `miEquipo`.
  delegador: boolean;
};

const Ctx = createContext<TareasCtx | null>(null);

export const TareasProvider = Ctx.Provider;

export function useTareas() {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error("useTareas fuera de TareasProvider");
  return ctx;
}

// Sin nombre visible: la base no devolvió a esa persona o equipo.
export function useNombre() {
  const { nombres } = useTareas();
  return (id: string | null) => (id ? (nombres[id] ?? "—") : "—");
}
