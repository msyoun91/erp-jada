"use client";

import { useState } from "react";
import { CalendarClock, Clock, History, Lock } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { diasEntreISO, formatFecha, hoyISO } from "@/lib/utils";
import { HiloDetailPanel } from "./HiloDetailPanel";
import { CerrarHiloModal } from "./CerrarHiloModal";

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
  usuarioActualId,
  gestionarAjenas,
  autoAbrir,
}: {
  hilo: TareaHilo;
  tareas: TareaConAsignados[];
  proyectos: TareaProyecto[];
  usuarios: Usuario[];
  plantillas: TareaPlantilla[];
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
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

  // §5 spec: al completarse la última tarea pendiente del hilo, preguntar si
  // se quiere cerrar — se dispara solo en la transición (no en cada render)
  // comparando contra la última "firma" de estados vista, mismo patrón que
  // TareaRow usa para reconciliar estado optimista sin useEffect(setState).
  const sigActual = calcSig(tareasDelHilo);
  const [sigBase, setSigBase] = useState(sigActual);
  const [mostrarCierreAuto, setMostrarCierreAuto] = useState(false);
  if (sigActual !== sigBase) {
    setSigBase(sigActual);
    const todasCompletas =
      tareasDelHilo.length > 0 && tareasDelHilo.every((t) => t.estado === "completada" || t.estado === "cancelada");
    if (todasCompletas && hilo.estado === "abierto") setMostrarCierreAuto(true);
  }

  const completadas = tareasDelHilo.filter((t) => t.estado === "completada").length;
  const creadoFecha = hilo.created_at.slice(0, 10);
  const diasTranscurridos = diasEntreISO(creadoFecha, hoyISO());

  const proximaFecha = tareasDelHilo
    .filter((t) => (t.estado === "pendiente" || t.estado === "en_progreso") && !t.posponer_hasta && t.fecha_vencimiento)
    .map((t) => t.fecha_vencimiento as string)
    .sort()[0];
  const diasProxima = proximaFecha ? diasEntreISO(hoyISO(), proximaFecha) : null;

  return (
    <div className="rounded-lg border border-border bg-bg-surface">
      <button
        className="flex w-full items-center gap-2 p-[13px] px-5 text-left"
        onClick={() => setDetalleAbierto(true)}
      >
        <p className="t-body-m min-w-0 flex-1 truncate font-semibold text-text-primary">{hilo.titulo}</p>
        {proyecto && <span className="badge badge-neutral shrink-0">{proyecto.nombre}</span>}
        <span className={`badge shrink-0 ${hilo.estado === "cerrado" ? "badge-neutral" : "badge-info"}`}>
          {hilo.estado === "cerrado" ? "Cerrado" : "Abierto"}
        </span>
        <span className="t-caption shrink-0 whitespace-nowrap">
          {completadas}/{tareasDelHilo.length} completadas
        </span>
      </button>

      <div className="flex flex-wrap items-center gap-3 px-5 pb-3 t-caption">
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
        <span className="flex items-center gap-1">
          <History size={13} strokeWidth={1.75} />
          Hace {diasTranscurridos} {diasTranscurridos === 1 ? "día" : "días"}
        </span>
        {proximaFecha ? (
          <span
            className={`flex items-center gap-1 ${
              diasProxima !== null && diasProxima < 0
                ? "text-error"
                : diasProxima !== null && diasProxima <= 3
                  ? "text-warning"
                  : ""
            }`}
          >
            <CalendarClock size={13} strokeWidth={1.75} />
            {diasProxima !== null && diasProxima < 0
              ? `Próxima tarea vencida hace ${Math.abs(diasProxima)} días`
              : diasProxima === 0
                ? "Próxima tarea vence hoy"
                : `Próxima tarea vence en ${diasProxima} días`}
          </span>
        ) : (
          <span className="flex items-center gap-1">
            <CalendarClock size={13} strokeWidth={1.75} />
            Sin tareas activas con vencimiento
          </span>
        )}
      </div>

      {detalleAbierto && (
        <HiloDetailPanel
          hilo={hilo}
          tareasDelHilo={tareasDelHilo}
          proyecto={proyecto}
          proyectos={proyectos}
          usuarios={usuarios}
          plantillas={plantillas}
          usuarioActualId={usuarioActualId}
          gestionarAjenas={gestionarAjenas}
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
    </div>
  );
}
