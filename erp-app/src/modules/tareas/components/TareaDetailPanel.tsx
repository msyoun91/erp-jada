"use client";

import { useState } from "react";
import { toast } from "sonner";
import {
  Archive,
  ArrowRightLeft,
  CalendarClock,
  Clock,
  ExternalLink,
  GitBranch,
  Lock,
  Pencil,
  Repeat,
  Thermometer,
  Unlink,
  UserCog,
} from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { ConfirmModal } from "@/components/ui/Modal";
import {
  asociarTareaHilo,
  convertirTareaEnHilo,
  desactivarTarea,
  desasociarTareaHilo,
} from "../actions";
import type { TareaConAsignados, TareaHilo, TareaProyecto, Usuario } from "../types";
import { diasEntreISO, formatFecha, hoyISO } from "@/lib/utils";
import { ReasignarPanel } from "./ReasignarPanel";
import { PosponerPanel } from "./PosponerPanel";
import { CompletarModal } from "./CompletarModal";
import { TareaFormPanel } from "./TareaFormPanel";
import { NotasSection } from "./NotasSection";
import { ESTADO_BADGE, ESTADO_LABEL, RECURRENCIA_LABEL, temperaturaRango } from "./tareaLabels";

// Umbrales fijos — spec pide "configurable" pero no hay un segundo caso real
// todavía que justifique una UI de settings para esto (simplicidad antes que
// abstracción). Ajustar acá si en el futuro se necesita por tipo de tarea.
const PROXIMA_DIAS = 3;

// Todo lo que se hace y se lee de una tarea: la isla (TareaCard) solo resume.
// El estado y la temperatura optimistas viven en la isla y bajan por props —
// así el badge de la isla y el control del panel muestran siempre lo mismo.
export function TareaDetailPanel({
  tarea,
  usuarios,
  proyectos,
  miembrosPorProyecto,
  hilosDisponibles,
  proyectoHeredadoId,
  usuarioActualId,
  gestionarAjenas,
  puedeAsignar,
  estado,
  temperatura,
  onCambiarEstado,
  onTemperaturaInput,
  onTemperaturaCommit,
  onConvertida,
  onClose,
}: {
  tarea: TareaConAsignados;
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  miembrosPorProyecto: Record<string, string[]>;
  hilosDisponibles?: TareaHilo[];
  proyectoHeredadoId?: string | null;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  puedeAsignar: boolean;
  estado: string;
  temperatura: number;
  onCambiarEstado: (nuevo: "pendiente" | "en_progreso" | "cancelada") => void;
  onTemperaturaInput: (valor: number) => void;
  onTemperaturaCommit: () => void;
  onConvertida?: (hiloId: string) => void;
  onClose: () => void;
}) {
  const [reasignando, setReasignando] = useState(false);
  const [posponiendo, setPosponiendo] = useState(false);
  const [completando, setCompletando] = useState(false);
  const [editando, setEditando] = useState(false);
  const [mostrandoMoverHilo, setMostrandoMoverHilo] = useState(false);
  const [desactivando, setDesactivando] = useState(false);

  const proyectoEfectivo = tarea.proyecto_id ?? proyectoHeredadoId ?? null;
  const miembros = proyectoEfectivo ? (miembrosPorProyecto[proyectoEfectivo] ?? []) : null;
  const proyectoNombre = proyectoEfectivo
    ? (proyectos.find((p) => p.id === proyectoEfectivo)?.nombre ?? undefined)
    : undefined;

  const asignadosActivos = tarea.tareas_asignados.filter((a) => a.activo);
  const responsable = usuarios.find((u) => u.id === tarea.responsable_id)?.nombre ?? null;

  // Sin creado_por: haber creado la tarea no da autoridad sobre ella (la da
  // ser responsable o tener asignación activa). Mostrar acciones que la RLS
  // descarta en silencio — un UPDATE denegado afecta 0 filas, no tira error —
  // es peor que ocultarlas.
  const esAsignado =
    gestionarAjenas ||
    tarea.responsable_id === usuarioActualId ||
    asignadosActivos.some((a) => a.usuario_id === usuarioActualId);
  const puedeGestionar = gestionarAjenas || tarea.responsable_id === usuarioActualId;

  const activa = estado !== "completada" && estado !== "cancelada";
  const diasVencimiento = tarea.fecha_vencimiento ? diasEntreISO(hoyISO(), tarea.fecha_vencimiento) : null;
  const vencida = activa && diasVencimiento !== null && diasVencimiento < 0;
  const proximaAVencer = activa && diasVencimiento !== null && diasVencimiento >= 0 && diasVencimiento <= PROXIMA_DIAS;
  const fechaClase = vencida ? "text-error" : proximaAVencer ? "text-warning" : "";

  async function moverAHilo(hiloId: string) {
    if (!hiloId) return;
    const result = await asociarTareaHilo(tarea.id, hiloId);
    if (!result.success) toast.error(result.error);
    else onClose();
  }

  async function quitarDeHilo() {
    const result = await desasociarTareaHilo(tarea.id);
    if (!result.success) toast.error(result.error);
  }

  // La tarea pasa a ser el primer paso de un hilo nuevo con su mismo título y
  // descripción; el padre abre el panel del hilo para seguir agregando pasos.
  async function convertirEnHilo() {
    const result = await convertirTareaEnHilo(tarea.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    onConvertida?.(result.hiloId);
    onClose();
  }

  async function desactivar() {
    const result = await desactivarTarea(tarea.id);
    if (!result.success) toast.error(result.error);
    else onClose();
  }

  return (
    <RightPanel title={tarea.titulo} subtitle={proyectoNombre} onClose={onClose}>
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        {(esAsignado || puedeGestionar) && (
          <div className="flex flex-wrap items-center gap-2 border-b border-border p-[13px] px-5">
            {esAsignado && (
              <>
                {estado !== "completada" && (
                  <button className="btn btn-primary btn-sm" onClick={() => setCompletando(true)}>
                    Completar
                  </button>
                )}
                <select
                  className="input w-auto py-1.5 text-[13px]"
                  value={estado === "completada" ? "" : estado}
                  onChange={(e) => onCambiarEstado(e.target.value as "pendiente" | "en_progreso" | "cancelada")}
                  aria-label="Estado"
                >
                  {estado === "completada" && <option value="">Completada</option>}
                  <option value="pendiente">Pendiente</option>
                  <option value="en_progreso">En progreso</option>
                  <option value="cancelada">Cancelada</option>
                </select>
              </>
            )}

            <OverflowMenu
              items={[
                ...(esAsignado
                  ? [
                      {
                        label: "Modificar tarea",
                        icon: <Pencil size={14} strokeWidth={1.75} />,
                        onClick: () => setEditando(true),
                      },
                    ]
                  : []),
                ...(puedeGestionar
                  ? [
                      { label: "Posponer", icon: <Clock size={14} strokeWidth={1.75} />, onClick: () => setPosponiendo(true) },
                      ...(puedeAsignar
                        ? [
                            {
                              label: "Reasignar",
                              icon: <UserCog size={14} strokeWidth={1.75} />,
                              onClick: () => setReasignando(true),
                            },
                          ]
                        : []),
                      ...(tarea.hilo_id
                        ? [{ label: "Quitar del hilo", icon: <Unlink size={14} strokeWidth={1.75} />, onClick: quitarDeHilo }]
                        : [
                            {
                              label: "Agregar paso",
                              icon: <GitBranch size={14} strokeWidth={1.75} />,
                              onClick: convertirEnHilo,
                            },
                            ...(hilosDisponibles && hilosDisponibles.length > 0
                              ? [
                                  {
                                    label: "Mover a hilo…",
                                    icon: <ArrowRightLeft size={14} strokeWidth={1.75} />,
                                    onClick: () => setMostrandoMoverHilo(true),
                                  },
                                ]
                              : []),
                          ]),
                      {
                        label: "Desactivar",
                        icon: <Archive size={14} strokeWidth={1.75} />,
                        onClick: () => setDesactivando(true),
                        destructive: true,
                      },
                    ]
                  : []),
              ]}
            />
          </div>
        )}

        {mostrandoMoverHilo && hilosDisponibles && (
          <select
            className="input mx-5 mt-3 w-auto py-1.5 text-[13px]"
            value=""
            autoFocus
            onChange={(e) => {
              moverAHilo(e.target.value);
              setMostrandoMoverHilo(false);
            }}
            onBlur={() => setMostrandoMoverHilo(false)}
          >
            <option value="">Mover a hilo…</option>
            {hilosDisponibles.map((h) => (
              <option key={h.id} value={h.id}>
                {h.titulo}
              </option>
            ))}
          </select>
        )}

        <div className="flex flex-col gap-3 border-b border-border p-[13px] px-5">
          <div className="flex flex-wrap items-center gap-2">
            <span className={`badge ${ESTADO_BADGE[estado]}`}>{ESTADO_LABEL[estado]}</span>
            {tarea.visibilidad === "privado" && tarea.hilo_id === null && (
              <span className="t-caption flex items-center gap-1">
                <Lock size={13} strokeWidth={1.75} />
                Privada
              </span>
            )}
          </div>

          {tarea.descripcion && <p className="t-body-m whitespace-pre-wrap">{tarea.descripcion}</p>}

          <div className="t-caption flex flex-wrap items-center gap-3">
            <span className={`flex items-center gap-1 ${fechaClase}`}>
              <CalendarClock size={13} strokeWidth={1.75} />
              {tarea.fecha_vencimiento
                ? `Vence ${formatFecha(tarea.fecha_vencimiento)}`
                : `Creada hace ${diasEntreISO(tarea.created_at.slice(0, 10), hoyISO())} días`}
            </span>
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
          </div>

          {activa && esAsignado && (
            <div className="flex items-center gap-2">
              <span className={`t-caption flex items-center gap-1 ${temperaturaRango(temperatura).clase}`}>
                <Thermometer size={13} strokeWidth={1.75} />
                {temperaturaRango(temperatura).label} ({temperatura})
              </span>
              <input
                type="range"
                min={1}
                max={100}
                value={temperatura}
                onChange={(e) => onTemperaturaInput(Number(e.target.value))}
                onMouseUp={onTemperaturaCommit}
                onTouchEnd={onTemperaturaCommit}
                onKeyUp={onTemperaturaCommit}
                onBlur={onTemperaturaCommit}
                className="w-32 accent-brand-700"
                aria-label="Temperatura"
              />
            </div>
          )}

          <p className="t-caption">
            Responsable: {responsable ?? "—"}
            {asignadosActivos.length > 0 &&
              ` · Asignados: ${asignadosActivos.map((a) => a.usuarios?.nombre ?? "—").join(", ")}`}
          </p>
        </div>

        <div className="p-[13px] px-5">
          <p className="t-label mb-2">Notas</p>
          <NotasSection tipo="tarea" id={tarea.id} puedeAgregar={esAsignado} notasIniciales={tarea.tareas_notas} />
        </div>
      </div>

      {desactivando && (
        <ConfirmModal
          title="Desactivar tarea"
          mensaje={`¿Desactivar la tarea "${tarea.titulo}"?`}
          onConfirm={desactivar}
          onClose={() => setDesactivando(false)}
        />
      )}
      {reasignando && (
        <ReasignarPanel
          tareaId={tarea.id}
          asignadosActuales={asignadosActivos.map((a) => a.usuario_id)}
          responsableActual={tarea.responsable_id}
          usuarios={usuarios}
          miembros={miembros}
          onClose={() => setReasignando(false)}
        />
      )}
      {posponiendo && (
        <PosponerPanel tipo="tarea" id={tarea.id} titulo={tarea.titulo} onClose={() => setPosponiendo(false)} />
      )}
      {completando && (
        <CompletarModal tareaId={tarea.id} titulo={tarea.titulo} onClose={() => setCompletando(false)} />
      )}
      {editando && (
        <TareaFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          puedeAsignar={puedeAsignar}
          proyectoHeredadoId={proyectoHeredadoId}
          tarea={tarea}
          onClose={() => setEditando(false)}
        />
      )}
    </RightPanel>
  );
}
