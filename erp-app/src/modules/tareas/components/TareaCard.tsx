"use client";

import { useState } from "react";
import { CalendarClock, Clock } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaProyecto, Usuario } from "../types";
import { diasEntreISO, formatFecha, hoyISO } from "@/lib/utils";
import { relacionTarea } from "../relacion";
import { useTareaOptimista } from "../useTareaOptimista";
import { Isla } from "./Isla";
import { TareaDetailPanel } from "./TareaDetailPanel";
import {
  ESTADO_BADGE,
  ESTADO_LABEL,
  RECURRENCIA_LABEL,
  estadoVencimiento,
  iniciales,
  temperaturaRango,
  textoAntiguedad,
} from "./tareaLabels";
import type { PasoEnCadena } from "./cadenaPasos";

// Umbrales fijos — spec pide "configurable" pero no hay un segundo caso real
// todavía que justifique una UI de settings para esto (simplicidad antes que
// abstracción). Ajustar acá si en el futuro se necesita por tipo de tarea.
const ANTIGUEDAD_AMBAR_DIAS = 14;
const ANTIGUEDAD_ROJO_DIAS = 30;

// Isla resumen de la tarea, misma cara que HiloCard y ProyectoCard: click →
// panel derecho con todo el detalle y las acciones. El estado y la temperatura
// optimistas viven acá y no en el panel porque la isla los sigue mostrando
// cuando el panel está cerrado, y el orden por temperatura de la vista se
// refresca apenas se elige el nivel, sin esperar al server.
export function TareaCard({
  tarea,
  usuarios,
  proyectos,
  miembrosPorProyecto,
  hilosDisponibles,
  proyectoHeredadoId,
  usuarioActualId,
  gestionarAjenas,
  puedeAsignar,
  cadena,
  relacionCon,
  grande,
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
  puedeAsignar: boolean;
  // Posición en la cadena de pasos, si la tarea es parte de una.
  cadena?: PasoEnCadena;
  // Usuario cuya relación con la tarea se explica en el badge — el del filtro
  // de la vista, no necesariamente el actual.
  relacionCon?: string | null;
  // Misión muestra una sola tarea: la isla se despliega en vez de comprimirse.
  grande?: boolean;
  onTemperaturaChange?: (id: string, temperatura: number) => void;
  onConvertida?: (hiloId: string) => void;
}) {
  const [detalleAbierto, setDetalleAbierto] = useState(false);
  const { estado, temperatura, cambiarEstado, cambiarTemperatura } = useTareaOptimista(
    tarea,
    onTemperaturaChange,
  );

  const asignadosActivos = tarea.tareas_asignados.filter((a) => a.activo);

  // El badge existe para explicar por qué la fila aparece cuando el avatar no
  // lo hace: el usuario es responsable sin estar asignado. Si está asignado, el
  // avatar ya lo dice y el badge sería ruido.
  const relacion =
    relacionCon && !asignadosActivos.some((a) => a.usuario_id === relacionCon)
      ? relacionTarea(tarea, relacionCon) === "responsable"
        ? "Responsable"
        : null
      : null;
  const relacionNombre = usuarios.find((u) => u.id === relacionCon)?.nombre ?? "";

  const { activa, fechaClase } = estadoVencimiento(tarea.fecha_vencimiento, estado);

  const diasAntiguedad = !tarea.fecha_vencimiento ? diasEntreISO(tarea.created_at.slice(0, 10), hoyISO()) : null;
  const antiguedadClase =
    diasAntiguedad === null
      ? ""
      : diasAntiguedad >= ANTIGUEDAD_ROJO_DIAS
        ? "text-error-text"
        : diasAntiguedad >= ANTIGUEDAD_AMBAR_DIAS
          ? "text-warning-text"
          : "";

  // Dos niveles en la meta. Arriba lo que cambia la decisión de qué hacer
  // ahora (cuándo vence, si está pospuesta, quién la tiene); abajo el
  // contexto, que antes eran tres spans del mismo peso que el vencimiento.
  // Sigue siendo texto y no ícono pelado: en touch no hay hover del que colgar
  // un `title`.
  const contexto = [
    tarea.visibilidad === "privado" && tarea.hilo_id === null ? "Privada" : null,
    tarea.recurrencia_cantidad != null
      ? `Cada ${tarea.recurrencia_cantidad} ${RECURRENCIA_LABEL[tarea.recurrencia_unidad ?? "dia"]}`
      : null,
    tarea.origen_app,
  ].filter((c): c is string => Boolean(c));

  return (
    <>
      <Isla
        titulo={tarea.titulo}
        atenuada={!activa}
        barra={activa ? temperaturaRango(temperatura).barra : undefined}
        grande={grande}
        onAbrir={() => setDetalleAbierto(true)}
        badges={
          <>
            <span className={`badge shrink-0 ${ESTADO_BADGE[estado]}`}>{ESTADO_LABEL[estado]}</span>
            {/* Un conteo no es un estado: va como texto, igual que "N/M
                terminados" en el hilo y el proyecto. Los badges quedan para
                estado y bloqueo, que sí son la situación de la tarea. */}
            {cadena && (
              <span className="t-caption shrink-0 whitespace-nowrap">
                Paso {cadena.posicion}/{cadena.total}
              </span>
            )}
            {cadena?.bloqueada && activa && <span className="badge badge-warning shrink-0">Bloqueada</span>}
            {relacion && (
              <span className="badge badge-neutral shrink-0" title={`${relacion}: ${relacionNombre}`}>
                {relacion}
              </span>
            )}
          </>
        }
        meta={
          <div className="flex w-full flex-col gap-1.5">
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[13px] font-medium text-text-secondary">
              {tarea.fecha_vencimiento ? (
                <span className={`flex items-center gap-1 ${fechaClase}`}>
                  <CalendarClock size={14} strokeWidth={1.75} />
                  {formatFecha(tarea.fecha_vencimiento)}
                </span>
              ) : (
                <span className={`flex items-center gap-1 ${antiguedadClase}`}>
                  <CalendarClock size={14} strokeWidth={1.75} />
                  Creada {textoAntiguedad(diasAntiguedad ?? 0)}
                </span>
              )}
              {tarea.posponer_hasta && (
                <span className="flex items-center gap-1 text-warning-text">
                  <Clock size={14} strokeWidth={1.75} />
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
            </div>

            {contexto.length > 0 &&
              (grande ? (
                <div className="flex flex-wrap items-center gap-3">
                  {contexto.map((c) => (
                    <span key={c}>{c}</span>
                  ))}
                </div>
              ) : (
                <span className="truncate">{contexto.join(" · ")}</span>
              ))}
          </div>
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
          puedeAsignar={puedeAsignar}
          estado={estado}
          temperatura={temperatura}
          cadena={cadena}
          onCambiarEstado={cambiarEstado}
          onTemperaturaChange={cambiarTemperatura}
          onConvertida={onConvertida}
          onClose={() => setDetalleAbierto(false)}
        />
      )}
    </>
  );
}
