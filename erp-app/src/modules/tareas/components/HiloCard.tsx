"use client";

import { useState } from "react";
import { Clock, Lock, UserRound } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { formatFecha } from "@/lib/utils";
import { HiloDetailPanel } from "./HiloDetailPanel";
import { CerrarHiloModal } from "./CerrarHiloModal";
import { Isla } from "./Isla";
import { MetricasResumen, contarCompletadas } from "./MetricasResumen";

function calcSig(tareas: TareaConAsignados[]) {
  return tareas
    .map((t) => `${t.id}:${t.estado}`)
    .sort()
    .join(",");
}

// Isla resumen del hilo en la vista "Mis tareas": sin acciones ni tareas
// inline — eso vive en HiloDetailPanel, que se abre al hacer click.
export function HiloCard({
  hilo,
  tareas,
  proyectos,
  usuarios,
  plantillas,
  miembrosPorProyecto,
  usuarioActualId,
  gestionarAjenas,
  relacionCon,
  autoAbrir,
}: {
  hilo: TareaHilo;
  tareas: TareaConAsignados[];
  proyectos: TareaProyecto[];
  usuarios: Usuario[];
  plantillas: TareaPlantilla[];
  miembrosPorProyecto: Record<string, string[]>;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  relacionCon?: string | null;
  autoAbrir?: boolean;
}) {
  const [detalleAbierto, setDetalleAbierto] = useState(autoAbrir ?? false);

  // Al convertir una tarea en hilo el padre pide abrir este panel. La card
  // puede montarse antes o después de ese pedido (depende de si el
  // revalidatePath llega primero), así que se reacciona al cambio de prop
  // durante el render — no en un efecto (react-hooks/set-state-in-effect).
  const [autoAbrirBase, setAutoAbrirBase] = useState(autoAbrir);
  if (autoAbrir !== autoAbrirBase) {
    setAutoAbrirBase(autoAbrir);
    if (autoAbrir) setDetalleAbierto(true);
  }

  const tareasDelHilo = tareas.filter((t) => t.hilo_id === hilo.id);
  const proyecto = hilo.proyecto_id ? (proyectos.find((p) => p.id === hilo.proyecto_id) ?? null) : null;
  const responsable = usuarios.find((u) => u.id === hilo.responsable_id)?.nombre ?? null;

  // §5 spec: al completarse la última tarea pendiente del hilo, preguntar si
  // se quiere cerrar — se dispara solo en la transición (no en cada render)
  // comparando contra la última "firma" de estados vista, mismo patrón que
  // TareaCard usa para reconciliar estado optimista sin useEffect(setState).
  const sigActual = calcSig(tareasDelHilo);
  const [sigBase, setSigBase] = useState(sigActual);
  const [mostrarCierreAuto, setMostrarCierreAuto] = useState(false);
  if (sigActual !== sigBase) {
    setSigBase(sigActual);
    const todasCompletas =
      tareasDelHilo.length > 0 && tareasDelHilo.every((t) => t.estado === "completada" || t.estado === "cancelada");
    if (todasCompletas && hilo.estado === "abierto") setMostrarCierreAuto(true);
  }

  const completadas = contarCompletadas(tareasDelHilo);

  return (
    <>
      <Isla
        titulo={hilo.titulo}
        onAbrir={() => setDetalleAbierto(true)}
        badges={
          <>
            {proyecto && <span className="badge badge-neutral shrink-0">{proyecto.nombre}</span>}
            <span className={`badge shrink-0 ${hilo.estado === "cerrado" ? "badge-neutral" : "badge-info"}`}>
              {hilo.estado === "cerrado" ? "Cerrado" : "Abierto"}
            </span>
            <span className="t-caption shrink-0 whitespace-nowrap">
              {completadas}/{tareasDelHilo.length} completadas
            </span>
          </>
        }
        meta={
          <>
            {responsable && (
              <span className="flex items-center gap-1" title="Dueño del hilo">
                <UserRound size={13} strokeWidth={1.75} />
                {responsable}
              </span>
            )}
            {hilo.visibilidad === "privado" && (
              <span className="flex items-center gap-1">
                <Lock size={13} strokeWidth={1.75} />
                Privado
              </span>
            )}
            {hilo.posponer_hasta && (
              <span className="flex items-center gap-1 text-warning">
                <Clock size={13} strokeWidth={1.75} />
                Pospuesto hasta {formatFecha(hilo.posponer_hasta)}
              </span>
            )}
            <MetricasResumen createdAt={hilo.created_at} tareas={tareasDelHilo} />
          </>
        }
      />

      {detalleAbierto && (
        <HiloDetailPanel
          hilo={hilo}
          tareasDelHilo={tareasDelHilo}
          proyecto={proyecto}
          proyectos={proyectos}
          usuarios={usuarios}
          plantillas={plantillas}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          gestionarAjenas={gestionarAjenas}
          relacionCon={relacionCon}
          onClose={() => setDetalleAbierto(false)}
        />
      )}

      {mostrarCierreAuto && (
        <CerrarHiloModal
          hiloId={hilo.id}
          hiloTitulo={hilo.titulo}
          tareas={tareasDelHilo}
          onClose={() => setMostrarCierreAuto(false)}
          onMantenerAbierto={() => setMostrarCierreAuto(false)}
        />
      )}
    </>
  );
}
