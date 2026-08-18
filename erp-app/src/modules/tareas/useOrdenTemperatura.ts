"use client";

import { useState } from "react";
import type { TareaConAsignados } from "./types";

// Orden de "Mis tareas": temperatura más alta arriba, se refresca en vivo
// mientras se arrastra el slider (no recién al confirmar en el server) —
// por eso el override vive acá, no en cada TareaRow por separado.
export function useOrdenTemperatura() {
  const [overrides, setOverrides] = useState<Record<string, number>>({});

  function ordenar<T extends TareaConAsignados>(tareas: T[]): T[] {
    return [...tareas].sort((a, b) => (overrides[b.id] ?? b.temperatura) - (overrides[a.id] ?? a.temperatura));
  }

  function onTemperaturaChange(id: string, temperatura: number) {
    setOverrides((prev) => ({ ...prev, [id]: temperatura }));
  }

  return { ordenar, onTemperaturaChange };
}
