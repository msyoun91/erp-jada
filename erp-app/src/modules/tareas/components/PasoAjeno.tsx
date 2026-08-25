"use client";

import { useState } from "react";
import { Check, Circle, MessageSquare } from "lucide-react";
import type { TareaConAsignados, TareaProyecto, Usuario } from "../types";
import { diasEntreISO, hoyISO } from "@/lib/utils";
import { useTareaOptimista } from "../useTareaOptimista";
import { TareaDetailPanel } from "./TareaDetailPanel";
import { ESTADO_LABEL } from "./tareaLabels";
import type { PasoEnCadena } from "./cadenaPasos";

// Un paso del hilo que no es del usuario: se ve para saber si lo que necesito
// ya está hecho, no para trabajarlo. Deliberadamente NO usa Isla — la
// diferencia de peso visual contra las tareas propias es lo que evita que el
// hilo expandido vuelva a esconder el trabajo de uno.
export function PasoAjeno({
  tarea,
  usuarios,
  proyectos,
  miembrosPorProyecto,
  proyectoHeredadoId,
  usuarioActualId,
  gestionarAjenas,
  puedeAsignar,
  cadena,
}: {
  tarea: TareaConAsignados;
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  miembrosPorProyecto: Record<string, string[]>;
  proyectoHeredadoId?: string | null;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  puedeAsignar: boolean;
  // Posición en la cadena de pasos, si la tarea es parte de una.
  cadena?: PasoEnCadena;
}) {
  const [detalleAbierto, setDetalleAbierto] = useState(false);
  const { estado, temperatura, cambiarEstado, cambiarTemperatura } = useTareaOptimista(tarea);

  const completada = estado === "completada";
  const responsable = usuarios.find((u) => u.id === tarea.responsable_id)?.nombre ?? null;
  const notas = tarea.tareas_notas?.length ?? 0;

  // ponytail: `updated_at` como proxy de "cuándo se completó" — no hay columna
  // completada_en. Cualquier edición posterior lo corre. Si el dato importa de
  // verdad, agregar la columna antes que parchear acá.
  const diasDesde = completada ? diasEntreISO(tarea.updated_at.slice(0, 10), hoyISO()) : null;

  return (
    <>
      <button
        className="tap-target t-caption flex w-full items-center gap-2 px-5 py-2 text-left text-text-tertiary hover:bg-bg-subtle"
        onClick={() => setDetalleAbierto(true)}
      >
        {completada ? (
          <Check size={13} strokeWidth={2} className="shrink-0 text-success" />
        ) : (
          <Circle size={13} strokeWidth={1.75} className="shrink-0" />
        )}
        <span className={`min-w-0 flex-1 truncate ${completada ? "line-through" : ""}`}>{tarea.titulo}</span>
        {responsable && <span className="shrink-0">{responsable}</span>}
        <span className="shrink-0">
          {completada && diasDesde !== null
            ? diasDesde === 0
              ? "completada hoy"
              : `completada hace ${diasDesde} ${diasDesde === 1 ? "día" : "días"}`
            : ESTADO_LABEL[estado].toLowerCase()}
        </span>
        {notas > 0 && (
          <span className="flex shrink-0 items-center gap-1">
            <MessageSquare size={13} strokeWidth={1.75} />
            {notas}
          </span>
        )}
      </button>

      {detalleAbierto && (
        <TareaDetailPanel
          tarea={tarea}
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          proyectoHeredadoId={proyectoHeredadoId}
          usuarioActualId={usuarioActualId}
          gestionarAjenas={gestionarAjenas}
          puedeAsignar={puedeAsignar}
          cadena={cadena}
          estado={estado}
          temperatura={temperatura}
          onCambiarEstado={cambiarEstado}
          onTemperaturaChange={cambiarTemperatura}
          onClose={() => setDetalleAbierto(false)}
        />
      )}
    </>
  );
}
