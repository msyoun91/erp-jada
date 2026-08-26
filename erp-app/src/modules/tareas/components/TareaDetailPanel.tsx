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
  ListOrdered,
  Lock,
  Pencil,
  Plus,
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
import {
  ESTADO_BADGE,
  ESTADO_LABEL,
  RECURRENCIA_LABEL,
  TEMPERATURA_NIVELES,
  estadoVencimiento,
  temperaturaRango,
  textoAntiguedad,
} from "./tareaLabels";
import type { PasoEnCadena } from "./cadenaPasos";

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
  cadena,
  estado,
  temperatura,
  onCambiarEstado,
  onTemperaturaChange,
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
  // Posición en la cadena de pasos, si la tarea es parte de una.
  cadena?: PasoEnCadena;
  estado: string;
  temperatura: number;
  onCambiarEstado: (nuevo: "pendiente" | "en_progreso" | "cancelada") => void;
  onTemperaturaChange: (valor: number) => void;
  onConvertida?: (hiloId: string) => void;
  onClose: () => void;
}) {
  const [reasignando, setReasignando] = useState(false);
  const [posponiendo, setPosponiendo] = useState(false);
  const [completando, setCompletando] = useState(false);
  const [editando, setEditando] = useState(false);
  const [mostrandoMoverHilo, setMostrandoMoverHilo] = useState(false);
  const [agregandoPaso, setAgregandoPaso] = useState(false);
  const [desactivando, setDesactivando] = useState(false);
  const [cancelando, setCancelando] = useState(false);

  // El trigger `validar_paso_previo` (sql/017) rechaza pasar a en_progreso o
  // completada mientras el paso previo no esté completado. Cancelar sí se
  // puede: si no, una cadena con un paso trabado no se termina nunca.
  const bloqueada = cadena?.bloqueada ?? false;
  const pasoPrevio = cadena && cadena.posicion > 1 ? cadena.cadena[cadena.posicion - 2] : null;
  // Solo la cola de la cadena acepta un siguiente — la unique parcial de
  // `paso_anterior_id` no deja bifurcar.
  const puedeAgregarPaso = tarea.hilo_id !== null && (!cadena || cadena.posicion === cadena.total);

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

  const { activa, fechaClase } = estadoVencimiento(tarea.fecha_vencimiento, estado);

  async function moverAHilo(hiloId: string) {
    if (!hiloId) return;
    const result = await asociarTareaHilo(tarea.id, hiloId);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea movida al hilo");
    onClose();
  }

  // Única acción del panel que no lo cierra: sin toast no pasaba nada visible.
  async function quitarDeHilo() {
    const result = await desasociarTareaHilo(tarea.id);
    if (!result.success) toast.error(result.error);
    else toast.success("Tarea fuera del hilo");
  }

  // La tarea pasa a ser el primer paso de un hilo nuevo con su mismo título y
  // descripción; el padre abre el panel del hilo para seguir agregando pasos.
  async function convertirEnHilo() {
    const result = await convertirTareaEnHilo(tarea.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea convertida en hilo");
    onConvertida?.(result.hiloId);
    onClose();
  }

  async function desactivar() {
    const result = await desactivarTarea(tarea.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea desactivada");
    onClose();
  }

  // Cancelar saca la tarea de toda cola de trabajo: es un cambio de estado
  // importante y va con confirmación explícita, como completar (GUIDE_DESIGN).
  // Los otros dos estados del select no la necesitan — son reversibles y no
  // sacan la tarea de ningún lado.
  function elegirEstado(nuevo: "pendiente" | "en_progreso" | "cancelada") {
    if (nuevo === "cancelada") setCancelando(true);
    else onCambiarEstado(nuevo);
  }

  return (
    <RightPanel title={tarea.titulo} subtitle={proyectoNombre} onClose={onClose}>
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        {(esAsignado || puedeGestionar) && (
          <div className="flex flex-wrap items-center gap-2 border-b border-border row">
            {esAsignado && (
              <>
                {estado !== "completada" && !bloqueada && (
                  <button className="btn btn-primary btn-sm" onClick={() => setCompletando(true)}>
                    Completar
                  </button>
                )}
                <select
                  className="input w-auto py-1.5 text-[13px]"
                  value={estado === "completada" ? "" : estado}
                  onChange={(e) => elegirEstado(e.target.value as "pendiente" | "en_progreso" | "cancelada")}
                  aria-label="Estado"
                >
                  {estado === "completada" && <option value="">Completada</option>}
                  <option value="pendiente">Pendiente</option>
                  {/* Una tarea ya en progreso puede quedar bloqueada
                      (`reabrir_hilo_en_tarea` reabre el paso previo): sin su
                      propia opción el select mostraba "Pendiente" sobre una
                      tarea que no lo está. Se ve, no se puede elegir. */}
                  {(!bloqueada || estado === "en_progreso") && (
                    <option value="en_progreso" disabled={bloqueada}>
                      En progreso
                    </option>
                  )}
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
                      ...(puedeAgregarPaso
                        ? [
                            {
                              label: "Crear siguiente paso",
                              icon: <Plus size={14} strokeWidth={1.75} />,
                              onClick: () => setAgregandoPaso(true),
                            },
                          ]
                        : []),
                      ...(tarea.hilo_id
                        ? [{ label: "Quitar del hilo", icon: <Unlink size={14} strokeWidth={1.75} />, onClick: quitarDeHilo }]
                        : [
                            {
                              // Antes decía "Agregar paso", que ahora significa
                              // otra cosa: esto convierte la tarea en hilo.
                              label: "Convertir en hilo",
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

        <div className="flex flex-col gap-3 border-b border-border row">
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
                : `Creada ${textoAntiguedad(diasEntreISO(tarea.created_at.slice(0, 10), hoyISO()))}`}
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
              <span className="flex items-center gap-1 text-warning-text">
                <Clock size={13} strokeWidth={1.75} />
                Pospuesta hasta {formatFecha(tarea.posponer_hasta)}
              </span>
            )}
          </div>

          {activa && esAsignado && (
            <div className="flex flex-wrap items-center gap-2">
              <span className="t-caption flex items-center gap-1">
                <Thermometer size={13} strokeWidth={1.75} />
                Temperatura
              </span>
              <div className="flex gap-1" role="group" aria-label="Temperatura">
                {TEMPERATURA_NIVELES.map((nivel) => {
                  const activo = temperaturaRango(temperatura).label === nivel.label;
                  return (
                    <button
                      key={nivel.label}
                      type="button"
                      aria-pressed={activo}
                      className={`btn btn-sm ${activo ? temperaturaRango(nivel.valor).selector : "btn-secondary"}`}
                      onClick={() => onTemperaturaChange(nivel.valor)}
                    >
                      {nivel.label}
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          <p className="t-caption">
            Responsable: {responsable ?? "—"}
            {asignadosActivos.length > 0 &&
              ` · Asignados: ${asignadosActivos.map((a) => a.usuarios?.nombre ?? "—").join(", ")}`}
          </p>
        </div>

        {cadena && (
          <div className="flex flex-col gap-2 border-b border-border row">
            <p className="t-label flex items-center gap-1.5">
              <ListOrdered size={14} strokeWidth={1.75} />
              Paso {cadena.posicion} de {cadena.total}
            </p>
            {bloqueada && pasoPrevio && (
              <p className="t-caption text-warning-text">Bloqueada hasta completar «{pasoPrevio.titulo}»</p>
            )}
            <ol className="flex flex-col gap-1.5">
              {cadena.cadena.map((p, i) => {
                const actual = p.id === tarea.id;
                // El paso actual muestra el estado optimista del panel: la
                // misma tarea no puede leerse distinto según dónde se la mire.
                const estadoPaso = actual ? estado : p.estado;
                // Lo que dejaron los pasos previos es el contexto para
                // trabajar este: título entero y sus notas. Los que vienen
                // después todavía no dicen nada — siguen siendo una línea.
                const previo = i < cadena.posicion - 1;
                const notas = previo ? (p.tareas_notas ?? []) : [];
                return (
                  <li key={p.id} className={`t-caption ${actual ? "font-semibold text-text-primary" : ""}`}>
                    <div className="flex items-start gap-2">
                      <span className="w-4 shrink-0 tabular-nums">{i + 1}.</span>
                      <span className={`min-w-0 flex-1 ${previo ? "whitespace-pre-wrap" : "truncate"}`}>
                        {p.titulo}
                      </span>
                      <span className={`badge shrink-0 ${ESTADO_BADGE[estadoPaso]}`}>{ESTADO_LABEL[estadoPaso]}</span>
                    </div>
                    {notas.length > 0 && (
                      <div className="ml-6 mt-1.5 flex flex-col gap-1.5">
                        {notas.map((n) => (
                          <div key={n.id} className="rounded-md bg-bg-subtle p-2">
                            <p className="whitespace-pre-wrap text-text-secondary">{n.nota}</p>
                            <p className="mt-1">
                              {n.usuarios?.nombre ?? "—"} · {formatFecha(n.created_at)}
                            </p>
                          </div>
                        ))}
                      </div>
                    )}
                  </li>
                );
              })}
            </ol>
          </div>
        )}

        <div className="row">
          <p className="t-label mb-2">Notas</p>
          <NotasSection tipo="tarea" id={tarea.id} puedeAgregar={esAsignado} notasIniciales={tarea.tareas_notas} />
        </div>
      </div>

      {cancelando && (
        <ConfirmModal
          title="Cancelar tarea"
          mensaje={`¿Cancelar "${tarea.titulo}"? Sale de tu cola de trabajo; podés volver a ponerla en pendiente.`}
          confirmLabel="Cancelar la tarea"
          cancelLabel="Volver"
          onConfirm={() => onCambiarEstado("cancelada")}
          onClose={() => setCancelando(false)}
        />
      )}
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
      {agregandoPaso && tarea.hilo_id && (
        <TareaFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          puedeAsignar={puedeAsignar}
          hiloId={tarea.hilo_id}
          pasoAnteriorId={tarea.id}
          proyectoHeredadoId={proyectoHeredadoId}
          onClose={() => setAgregandoPaso(false)}
        />
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
