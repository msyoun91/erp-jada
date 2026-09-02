"use client";

import { useState } from "react";
import { ChevronDown, ChevronUp, Clock, Lock, UserRound } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaPlantilla } from "../types";
import { formatFecha } from "@/lib/utils";
import { relacionTarea } from "../relacion";
import { HiloDetailPanel } from "./HiloDetailPanel";
import { CerrarHiloModal } from "./CerrarHiloModal";
import { Isla } from "./Isla";
import { PasoAjeno } from "./PasoAjeno";
import { TareaCard } from "./TareaCard";
import { MetricasResumen, contarTerminadas } from "./MetricasResumen";
import { cadenasDePasos } from "./cadenaPasos";
import { esTerminada } from "./tareaFiltros";
import { useTareasContexto } from "./tareasContexto";

function calcSig(tareas: TareaConAsignados[]) {
  return tareas
    .map((t) => `${t.id}:${t.estado}`)
    .sort()
    .join(",");
}

// El hilo agrupa, no es una fila: la unidad accionable de la lista es la tarea.
// Colapsado muestra solo los pasos del usuario; expandido, todos en orden de
// secuencia (created_at, no temperatura) para contestar "¿ya está listo lo que
// necesito?". Los ajenos van como línea fina, no como card — esa diferencia de
// peso es lo que evita que un hilo de 20 pasos esconda los 2 propios.
export function HiloCard({
  hilo,
  tareas,
  plantillas,
  relacionCon,
  autoAbrir,
  onTemperaturaChange,
}: {
  hilo: TareaHilo;
  tareas: TareaConAsignados[];
  plantillas: TareaPlantilla[];
  relacionCon?: string | null;
  autoAbrir?: boolean;
  onTemperaturaChange?: (id: string, temperatura: number) => void;
}) {
  const { usuarios, proyectos, usuarioActualId, gestionarAjenas } = useTareasContexto();
  const [detalleAbierto, setDetalleAbierto] = useState(autoAbrir ?? false);
  // Local y efímero: se pierde al recargar. Persistirlo se agrega cuando moleste.
  const [expandido, setExpandido] = useState(false);

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
  // Cerrar el hilo es del dueño: ofrecérselo a cualquiera que tenga la card
  // montada era un modal cuya acción la RLS después rechaza.
  const puedeGestionar = gestionarAjenas || hilo.responsable_id === usuarioActualId;

  const sigActual = calcSig(tareasDelHilo);
  const [sigBase, setSigBase] = useState(sigActual);
  const [mostrarCierreAuto, setMostrarCierreAuto] = useState(false);
  if (sigActual !== sigBase) {
    setSigBase(sigActual);
    const todasTerminadas = tareasDelHilo.length > 0 && tareasDelHilo.every(esTerminada);
    if (todasTerminadas && hilo.estado === "abierto" && puedeGestionar) setMostrarCierreAuto(true);
  }

  const terminadas = contarTerminadas(tareasDelHilo);
  // Los pasos de la Lista se leen igual que en Misión y en el panel del hilo:
  // sin esto, la misma tarea mostraba su posición en la cadena en un lado y no
  // en el otro.
  const cadenas = cadenasDePasos(tareasDelHilo);

  // created_at asc = orden de los pasos: no hay columna `orden` y
  // agregarTareasDesdePlantilla inserta en el orden de la plantilla.
  const enSecuencia = [...tareasDelHilo].sort((a, b) => a.created_at.localeCompare(b.created_at));
  const esPropia = (t: TareaConAsignados) => (relacionCon ? relacionTarea(t, relacionCon) !== null : true);
  const propias = enSecuencia.filter(esPropia);
  const visibles = expandido ? enSecuencia : propias;
  const hayAjenos = tareasDelHilo.length > propias.length;

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
              {relacionCon &&
                `${propias.length === 0 ? "Sin pasos asignados" : `${propias.length} ${propias.length === 1 ? "tuyo" : "tuyos"}`} · `}
              {terminadas}/{tareasDelHilo.length} terminados
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
              <span className="flex items-center gap-1 text-warning-text">
                <Clock size={13} strokeWidth={1.75} />
                Pospuesto hasta {formatFecha(hilo.posponer_hasta)}
              </span>
            )}
            <MetricasResumen createdAt={hilo.created_at} tareas={tareasDelHilo} />
            {hayAjenos && (
              <button
                className="tap-target flex items-center gap-1 font-semibold text-brand-700"
                onClick={() => setExpandido(!expandido)}
              >
                {expandido ? (
                  <>
                    Ocultar
                    <ChevronUp size={13} strokeWidth={2} />
                  </>
                ) : (
                  <>
                    Ver los {tareasDelHilo.length} pasos
                    <ChevronDown size={13} strokeWidth={2} />
                  </>
                )}
              </button>
            )}
          </>
        }
      >
        {visibles.length > 0 && (
          <div className="flex flex-col gap-2 border-t border-border p-3">
            {visibles.map((t) =>
              esPropia(t) ? (
                <TareaCard
                  key={t.id}
                  tarea={t}
                  proyectoHeredadoId={hilo.proyecto_id}
                  cadena={cadenas.get(t.id)}
                  relacionCon={relacionCon}
                  onTemperaturaChange={onTemperaturaChange}
                />
              ) : (
                <PasoAjeno
                  key={t.id}
                  cadena={cadenas.get(t.id)}
                  tarea={t}
                  proyectoHeredadoId={hilo.proyecto_id}
                />
              ),
            )}
          </div>
        )}
      </Isla>

      {detalleAbierto && (
        <HiloDetailPanel
          hilo={hilo}
          tareasDelHilo={tareasDelHilo}
          proyecto={proyecto}
          plantillas={plantillas}
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
