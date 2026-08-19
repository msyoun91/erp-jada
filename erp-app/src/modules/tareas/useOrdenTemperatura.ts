"use client";

import { useState } from "react";
import type { TareaConAsignados } from "./types";

// Orden de "Mis tareas": temperatura más alta arriba, se refresca en vivo
// mientras se arrastra el slider (no recién al confirmar en el server) —
// por eso el override vive acá, no en cada TareaCard por separado.
export function useOrdenTemperatura() {
  const [overrides, setOverrides] = useState<Record<string, number>>({});

  // Completadas y canceladas al fondo, sin importar su temperatura: una tarea
  // cerrada en 90 no debe competir por atención con una pendiente en 40.
  function peso(t: TareaConAsignados) {
    return t.estado === "completada" || t.estado === "cancelada" ? 1 : 0;
  }

  function ordenar<T extends TareaConAsignados>(tareas: T[]): T[] {
    return [...tareas].sort(
      (a, b) => peso(a) - peso(b) || (overrides[b.id] ?? b.temperatura) - (overrides[a.id] ?? a.temperatura),
    );
  }

  function onTemperaturaChange(id: string, temperatura: number) {
    setOverrides((prev) => ({ ...prev, [id]: temperatura }));
  }

  return { ordenar, onTemperaturaChange };
}
