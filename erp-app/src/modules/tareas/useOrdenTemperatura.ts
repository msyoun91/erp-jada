"use client";

import { useState } from "react";
import type { TareaConAsignados } from "./types";

// Orden de "Mis tareas": temperatura más alta arriba, se refresca en vivo al
// cambiar de nivel (no recién al confirmar en el server) — por eso el override
// vive acá, no en cada TareaCard por separado.
export function useOrdenTemperatura() {
  const [overrides, setOverrides] = useState<Record<string, number>>({});

  // Completadas y canceladas al fondo, sin importar su temperatura: una tarea
  // cerrada en Alta no debe competir por atención con una pendiente en Media.
  function peso(t: TareaConAsignados) {
    return t.estado === "completada" || t.estado === "cancelada" ? 1 : 0;
  }

  function temp(t: TareaConAsignados) {
    return overrides[t.id] ?? t.temperatura;
  }

  // Con tres niveles en vez de 100 valores, la temperatura sola deja empates
  // grandes y el desempate caería en el orden del query (created_at desc, o
  // sea la más nueva arriba). Dentro del nivel manda lo que vence antes, y
  // entre las que no vencen, la más vieja.
  function vence(t: TareaConAsignados) {
    return t.fecha_vencimiento ?? "9999-12-31";
  }

  // Expuesto además de `ordenar` porque la vista Lista mezcla tareas sueltas
  // con grupos de hilo: el grupo se ordena por su paso propio más caliente, y
  // eso necesita comparar dos tareas que están en listas distintas.
  function comparar(a: TareaConAsignados, b: TareaConAsignados) {
    return (
      peso(a) - peso(b) ||
      temp(b) - temp(a) ||
      vence(a).localeCompare(vence(b)) ||
      a.created_at.localeCompare(b.created_at)
    );
  }

  function ordenar<T extends TareaConAsignados>(tareas: T[]): T[] {
    return [...tareas].sort(comparar);
  }

  function onTemperaturaChange(id: string, temperatura: number) {
    setOverrides((prev) => ({ ...prev, [id]: temperatura }));
  }

  return { ordenar, comparar, onTemperaturaChange };
}
