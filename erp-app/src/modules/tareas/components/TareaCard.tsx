"use client";

import { useState } from "react";
import { toast } from "sonner";
import { CalendarClock, Clock, ExternalLink, Lock, Repeat, Thermometer } from "lucide-react";
import { actualizarTemperatura, cambiarEstadoTarea } from "../actions";
import type { TareaConAsignados, TareaHilo, TareaProyecto, Usuario } from "../types";
import { diasEntreISO, formatFecha, hoyISO } from "@/lib/utils";
import { Isla } from "./Isla";
import { TareaDetailPanel } from "./TareaDetailPanel";
import { ESTADO_BADGE, ESTADO_LABEL, RECURRENCIA_LABEL, iniciales, temperaturaRango } from "./tareaLabels";

// Umbrales fijos — spec pide "configurable" pero no hay un segundo caso real
// todavía que justifique una UI de settings para esto (simplicidad antes que
// abstracción). Ajustar acá si en el futuro se necesita por tipo de tarea.
const PROXIMA_DIAS = 3;
const ANTIGUEDAD_AMBAR_DIAS = 14;
const ANTIGUEDAD_ROJO_DIAS = 30;

// Isla resumen de la tarea, misma cara que HiloCard y ProyectoCard: click →
// panel derecho con todo el detalle y las acciones. El estado y la temperatura
// optimistas viven acá y no en el panel porque la isla los sigue mostrando
// cuando el panel está cerrado, y el orden por temperatura de la vista se
// refresca mientras se arrastra el slider.
export function TareaCard({
  tarea,
  usuarios,
  proyectos,
  miembrosPorProyecto,
  hilosDisponibles,
  proyectoHeredadoId,
  usuarioActualId,
  gestionarAjenas,
  relacionCon,
  onTemperaturaChange,
  onConvertida,
}: {
  tarea: TareaConAsignados;
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  miembrosPorProyecto: Record<string, string[]>;
  hilosDisponibles?: TareaHilo[];
  // Proyecto del hilo que contiene la tarea (la tarea no lo guarda).
  proyectoHeredadoId?: string | null;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  // Usuario cuya relación con la tarea se explica en el badge — el del filtro
  // de la vista, no necesariamente el actual.
  relacionCon?: string | null;
  onTemperaturaChange?: (id: string, temperatura: number) => void;
  onConvertida?: (hiloId: string) => void;
}) {
  const [detalleAbierto, setDetalleAbierto] = useState(false);

  const [estadoBase, setEstadoBase] = useState(tarea.estado);
  const [estadoLocal, setEstadoLocal] = useState(tarea.estado);
  if (tarea.estado !== estadoBase) {
    setEstadoBase(tarea.estado);
    setEstadoLocal(tarea.estado);
  }

  const [tempBase, setTempBase] = useState(tarea.temperatura);
  const [tempLocal, setTempLocal] = useState(tarea.temperatura);
  if (tarea.temperatura !== tempBase) {
    setTempBase(tarea.temperatura);
    setTempLocal(tarea.temperatura);
  }

  const asignadosActivos = tarea.tareas_asignados.filter((a) => a.activo);

  // El badge existe para explicar por qué la fila aparece cuando el avatar no
  // lo hace: el usuario está involucrado como responsable o creador, sin estar
  // asignado. Si está asignado, el avatar ya lo dice y el badge sería ruido.
  const relacion =
    relacionCon && !asignadosActivos.some((a) => a.usuario_id === relacionCon)
      ? tarea.responsable_id === relacionCon
        ? "Responsable"
        : tarea.creado_por === relacionCon
          ? "Creador"
          : null
      : null;
  const relacionNombre = usuarios.find((u) => u.id === relacionCon)?.nombre ?? "";

  const activa = estadoLocal !== "completada" && estadoLocal !== "cancelada";
  const diasVencimiento = tarea.fecha_vencimiento ? diasEntreISO(hoyISO(), tarea.fecha_vencimiento) : null;
  const vencida = activa && diasVencimiento !== null && diasVencimiento < 0;
  const proximaAVencer = activa && diasVencimiento !== null && diasVencimiento >= 0 && diasVencimiento <= PROXIMA_DIAS;
  const fechaClase = vencida ? "text-error" : proximaAVencer ? "text-warning" : "";

  const diasAntiguedad = !tarea.fecha_vencimiento ? diasEntreISO(tarea.created_at.slice(0, 10), hoyISO()) : null;
  const antiguedadClase =
    diasAntiguedad === null
      ? ""
      : diasAntiguedad >= ANTIGUEDAD_ROJO_DIAS
        ? "text-error"
        : diasAntiguedad >= ANTIGUEDAD_AMBAR_DIAS
          ? "text-warning"
          : "";

  async function cambiarEstado(nuevo: "pendiente" | "en_progreso" | "cancelada") {
    const anterior = estadoLocal;
    setEstadoLocal(nuevo);
    const result = await cambiarEstadoTarea(tarea.id, nuevo);
    if (!result.success) {
      setEstadoLocal(anterior);
      toast.error(result.error);
    }
  }

  async function commitTemperatura() {
    if (tempLocal === tarea.temperatura) return;
    const result = await actualizarTemperatura(tarea.id, tempLocal);
    if (!result.success) {
      setTempLocal(tarea.temperatura);
      toast.error(result.error);
    }
  }

  function cambiarTemperatura(valor: number) {
    setTempLocal(valor);
    onTemperaturaChange?.(tarea.id, valor);
  }

  return (
    <>
      <Isla
        titulo={tarea.titulo}
        atenuada={!activa}
        onAbrir={() => setDetalleAbierto(true)}
        badges={
          <>
            <span className={`badge shrink-0 ${ESTADO_BADGE[estadoLocal]}`}>{ESTADO_LABEL[estadoLocal]}</span>
            {relacion && (
              <span className="badge badge-neutral shrink-0" title={`${relacion}: ${relacionNombre}`}>
                {relacion}
              </span>
            )}
          </>
        }
        meta={
          <>
            {tarea.fecha_vencimiento ? (
              <span className={`flex items-center gap-1 ${fechaClase}`}>
                <CalendarClock size={13} strokeWidth={1.75} />
                {formatFecha(tarea.fecha_vencimiento)}
              </span>
            ) : (
              <span className={`flex items-center gap-1 ${antiguedadClase}`}>
                <CalendarClock size={13} strokeWidth={1.75} />
                Creada hace {diasAntiguedad} {diasAntiguedad === 1 ? "día" : "días"}
              </span>
            )}
            {activa && (
              <span className={`flex items-center gap-1 ${temperaturaRango(tempLocal).clase}`}>
                <Thermometer size={13} strokeWidth={1.75} />
                {temperaturaRango(tempLocal).label} ({tempLocal})
              </span>
            )}
            {tarea.visibilidad === "privado" && (
              <span className="flex items-center gap-1">
                <Lock size={13} strokeWidth={1.75} />
                Privada
              </span>
            )}
            {tarea.recurrencia_cantidad != null && (
              <span className="flex items-center gap-1">
                <Repeat size={13} strokeWidth={1.75} />
                Cada {tarea.recurrencia_cantidad} {RECURRENCIA_LABEL[tarea.recurrencia_unidad ?? "dia"]}
              </span>
            )}
            {tarea.origen_app && (
              <span className="flex items-center gap-1">
                <ExternalLink size={13} strokeWidth={1.75} />
                {tarea.origen_app}
              </span>
            )}
            {tarea.posponer_hasta && (
              <span className="flex items-center gap-1 text-warning">
                <Clock size={13} strokeWidth={1.75} />
                Pospuesta hasta {formatFecha(tarea.posponer_hasta)}
              </span>
            )}
            {asignadosActivos.length > 0 && (
              <span className="flex items-center">
                {asignadosActivos.map((a, i) => (
                  <span
                    key={a.usuario_id}
                    title={a.usuarios?.nombre ?? ""}
                    style={{ marginLeft: i === 0 ? 0 : -6, zIndex: asignadosActivos.length - i }}
                    className={`flex h-5 w-5 items-center justify-center rounded-full bg-brand-50 text-[10px] font-semibold text-brand-700 ring-2 ring-bg-surface ${
                      a.usuario_id === usuarioActualId ? "outline outline-2 outline-brand-700" : ""
                    }`}
                  >
                    {a.usuarios ? iniciales(a.usuarios.nombre) : "?"}
                  </span>
                ))}
              </span>
            )}
          </>
        }
      />

      {detalleAbierto && (
        <TareaDetailPanel
          tarea={tarea}
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          hilosDisponibles={hilosDisponibles}
          proyectoHeredadoId={proyectoHeredadoId}
          usuarioActualId={usuarioActualId}
          gestionarAjenas={gestionarAjenas}
          estado={estadoLocal}
          temperatura={tempLocal}
          onCambiarEstado={cambiarEstado}
          onTemperaturaInput={cambiarTemperatura}
          onTemperaturaCommit={commitTemperatura}
          onConvertida={onConvertida}
          onClose={() => setDetalleAbierto(false)}
        />
      )}
    </>
  );
}
