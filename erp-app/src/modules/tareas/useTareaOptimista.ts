"use client";

import { useState } from "react";
import { toast } from "sonner";
import { actualizarTemperatura, cambiarEstadoTarea } from "./actions";
import type { TareaConAsignados } from "./types";

// Estado y temperatura optimistas de una tarea. Vive fuera del componente
// porque la tarea se muestra de dos formas (isla en TareaCard, línea fina en
// PasoAjeno) y ambas abren el mismo panel: si cada una llevara su propia copia
// del optimismo, la misma tarea podría leerse distinto según dónde se la abra.
export function useTareaOptimista(
  tarea: TareaConAsignados,
  onTemperaturaChange?: (id: string, temperatura: number) => void,
) {
  // Se reconcilia contra la prop durante el render y no en un efecto
  // (react-hooks/set-state-in-effect): el server pisa al optimista al revalidar.
  const [estadoBase, setEstadoBase] = useState(tarea.estado);
  const [estado, setEstado] = useState(tarea.estado);
  if (tarea.estado !== estadoBase) {
    setEstadoBase(tarea.estado);
    setEstado(tarea.estado);
  }

  const [tempBase, setTempBase] = useState(tarea.temperatura);
  const [temperatura, setTemperatura] = useState(tarea.temperatura);
  if (tarea.temperatura !== tempBase) {
    setTempBase(tarea.temperatura);
    setTemperatura(tarea.temperatura);
  }

  async function cambiarEstado(nuevo: "pendiente" | "en_progreso" | "cancelada") {
    const anterior = estado;
    setEstado(nuevo);
    const result = await cambiarEstadoTarea(tarea.id, nuevo);
    if (!result.success) {
      setEstado(anterior);
      toast.error(result.error);
    }
  }

  function cambiarTemperatura(valor: number) {
    setTemperatura(valor);
    onTemperaturaChange?.(tarea.id, valor);
  }

  async function commitTemperatura() {
    if (temperatura === tarea.temperatura) return;
    const result = await actualizarTemperatura(tarea.id, temperatura);
    if (!result.success) {
      setTemperatura(tarea.temperatura);
      toast.error(result.error);
    }
  }

  return { estado, temperatura, cambiarEstado, cambiarTemperatura, commitTemperatura };
}
