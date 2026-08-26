"use client";

import { CalendarClock, History } from "lucide-react";
import { diasEntreISO, hoyISO } from "@/lib/utils";
import type { TareaConAsignados } from "../types";
import { PROXIMA_DIAS, textoAntiguedad } from "./tareaLabels";
import { esActiva, esTerminada } from "./tareaFiltros";

export function contarTerminadas(tareas: TareaConAsignados[]): number {
  return tareas.filter(esTerminada).length;
}

function plural(dias: number): string {
  return dias === 1 ? "día" : "días";
}

// Métricas compartidas por la isla de hilo (HiloCard) y el panel de proyecto:
// antigüedad desde la creación + próximo vencimiento entre las tareas activas.
// Devuelve solo los <span>: el contenedor (y los chips propios de cada uno,
// como "Privado" o "Pospuesto") los pone quien la usa.
export function MetricasResumen({
  createdAt,
  tareas,
}: {
  createdAt: string;
  tareas: TareaConAsignados[];
}) {
  const diasTranscurridos = diasEntreISO(createdAt.slice(0, 10), hoyISO());

  const proximaFecha = tareas
    .filter(esActiva)
    .flatMap((t) => (t.fecha_vencimiento ? [t.fecha_vencimiento] : []))
    .sort()[0];
  const diasProxima = proximaFecha ? diasEntreISO(hoyISO(), proximaFecha) : null;

  return (
    <>
      <span className="flex items-center gap-1">
        <History size={13} strokeWidth={1.75} />
        Creado {textoAntiguedad(diasTranscurridos)}
      </span>
      {diasProxima === null ? (
        <span className="flex items-center gap-1">
          <CalendarClock size={13} strokeWidth={1.75} />
          Sin tareas activas con vencimiento
        </span>
      ) : (
        <span
          className={`flex items-center gap-1 ${
            diasProxima < 0 ? "text-error-text" : diasProxima <= PROXIMA_DIAS ? "text-warning-text" : ""
          }`}
        >
          <CalendarClock size={13} strokeWidth={1.75} />
          {diasProxima < 0
            ? `Próxima tarea vencida hace ${Math.abs(diasProxima)} ${plural(Math.abs(diasProxima))}`
            : diasProxima === 0
              ? "Próxima tarea vence hoy"
              : `Próxima tarea vence en ${diasProxima} ${plural(diasProxima)}`}
        </span>
      )}
    </>
  );
}
