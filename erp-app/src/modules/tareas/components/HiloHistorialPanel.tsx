"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { ChevronDown, ChevronRight, Clock, ClipboardList, Pencil, Plus, Trash2 } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { ConfirmModal } from "@/components/ui/ConfirmModal";
import { PosponerModal } from "@/components/ui/PosponerModal";
import {
  agregarTareasDesdePlantilla,
  desactivarHilo,
  obtenerHistorialHilo,
  obtenerPlantillas,
  posponerHilo,
  quitarPosposicionHilo,
} from "../actions";
import type { TareaConRelaciones, TareaHilo, TareaNota, TareaPlantilla } from "../types";
import { formatAntiguedad, formatPosponer, formatRecurrencia, HILO_ESTADO_BADGE, HILO_ESTADO_LABEL } from "./estado";
import { CrearHiloPanel } from "./CrearHiloPanel";
import { CrearTareaPanel } from "./CrearTareaPanel";
import { TareaNotasCard } from "./TareaNotasCard";

export function HiloHistorialPanel({
  hiloId,
  usuarioActualId,
  usuarios,
  puedeCrear,
  puedeAsignar,
  onClose,
}: {
  hiloId: string;
  usuarioActualId: string;
  usuarios: { id: string; nombre: string }[];
  puedeCrear: boolean;
  puedeAsignar: boolean;
  onClose: () => void;
}) {
  const [cargando, setCargando] = useState(true);
  const [hilo, setHilo] = useState<TareaHilo | null>(null);
  const [tareas, setTareas] = useState<TareaConRelaciones[]>([]);
  const [notas, setNotas] = useState<TareaNota[]>([]);
  const [plantillas, setPlantillas] = useState<TareaPlantilla[]>([]);
  const [modalCrearTarea, setModalCrearTarea] = useState(false);
  const [modalPlantilla, setModalPlantilla] = useState(false);
  const [modalEditarHilo, setModalEditarHilo] = useState(false);
  const [modalPosponer, setModalPosponer] = useState(false);
  const [confirmarEliminar, setConfirmarEliminar] = useState(false);
  const [eliminando, setEliminando] = useState(false);
  const [verCompletadas, setVerCompletadas] = useState(false);

  async function cargar() {
    const data = await obtenerHistorialHilo(hiloId);
    setHilo(data.hilo);
    setTareas(data.tareas);
    setNotas(data.notas);
    setCargando(false);
  }

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- fetch on demand al abrir el panel, no dato inicial de página
    cargar();
    if (puedeCrear) obtenerPlantillas().then(setPlantillas);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hiloId]);

  async function onEliminarHilo() {
    setEliminando(true);
    const result = await desactivarHilo(hiloId);
    setEliminando(false);
    setConfirmarEliminar(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo eliminado");
    onClose();
  }

  async function onPosponer(fecha: string) {
    const result = await posponerHilo({ hilo_id: hiloId, posponer_hasta: fecha });
    setModalPosponer(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo pospuesto");
    cargar();
  }

  async function onQuitarPosposicion() {
    const result = await quitarPosposicionHilo(hiloId);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    cargar();
  }

  const pendientes = tareas.filter((t) => t.estado !== "completada");
  const completadas = tareas.filter((t) => t.estado === "completada");
  const antiguedad = hilo ? formatAntiguedad(hilo) : null;

  return (
    <RightPanel
      title={hilo?.titulo ?? "Historial del hilo"}
      subtitle={
        hilo
          ? [HILO_ESTADO_LABEL[hilo.estado], formatRecurrencia(hilo), formatPosponer(hilo)].filter(Boolean).join(" · ")
          : undefined
      }
      onClose={onClose}
    >
      <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
        {cargando ? (
          <p className="t-caption">Cargando...</p>
        ) : (
          <>
            <div className="mb-3 flex items-center justify-between">
              {hilo && (
                <div className="flex items-center gap-2">
                  <span className={`badge ${HILO_ESTADO_BADGE[hilo.estado]}`}>{HILO_ESTADO_LABEL[hilo.estado]}</span>
                  <span className={`badge ${antiguedad?.badge}`}>{antiguedad?.texto}</span>
                </div>
              )}
              <div className="flex items-center gap-2">
                {puedeCrear && (
                  <>
                    <button className="btn btn-secondary btn-sm" onClick={() => setModalCrearTarea(true)}>
                      <Plus size={14} />
                      Nueva tarea
                    </button>
                    {plantillas.length > 0 && (
                      <button className="btn btn-secondary btn-sm" onClick={() => setModalPlantilla(true)}>
                        <ClipboardList size={14} />
                        Desde plantilla
                      </button>
                    )}
                    <button
                      className="text-text-tertiary hover:text-text-brand"
                      onClick={() => setModalEditarHilo(true)}
                      aria-label="Editar hilo"
                    >
                      <Pencil size={16} />
                    </button>
                    {hilo?.posponer_hasta ? (
                      <button className="t-caption text-text-brand" onClick={onQuitarPosposicion}>
                        Quitar posposición
                      </button>
                    ) : (
                      <button
                        className="text-text-tertiary hover:text-text-brand"
                        onClick={() => setModalPosponer(true)}
                        aria-label="Posponer hilo"
                      >
                        <Clock size={16} />
                      </button>
                    )}
                  </>
                )}
                {tareas.length === 0 && (
                  <button
                    className="text-text-tertiary hover:text-error"
                    onClick={() => setConfirmarEliminar(true)}
                    aria-label="Eliminar hilo"
                  >
                    <Trash2 size={16} />
                  </button>
                )}
              </div>
            </div>

            {tareas.length === 0 ? (
              <div className="empty-state">Sin tareas en este hilo todavía.</div>
            ) : (
              <>
                <div className="flex flex-col gap-3">
                  {pendientes.map((tarea) => (
                    <TareaNotasCard
                      key={tarea.id}
                      tarea={tarea}
                      notas={notas.filter((n) => n.tarea_id === tarea.id)}
                      onCambio={cargar}
                    />
                  ))}
                  {pendientes.length === 0 && (
                    <div className="empty-state">Sin tareas pendientes.</div>
                  )}
                </div>

                {completadas.length > 0 && (
                  <div className="mt-3">
                    <button
                      className="t-caption flex items-center gap-1 text-text-brand"
                      onClick={() => setVerCompletadas((v) => !v)}
                    >
                      {verCompletadas ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                      Tareas completadas ({completadas.length})
                    </button>

                    {verCompletadas && (
                      <div className="mt-2 flex flex-col gap-3">
                        {completadas.map((tarea) => (
                          <TareaNotasCard
                            key={tarea.id}
                            tarea={tarea}
                            notas={notas.filter((n) => n.tarea_id === tarea.id)}
                            onCambio={cargar}
                          />
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </>
            )}
          </>
        )}
      </div>

      {modalCrearTarea && (
        <CrearTareaPanel
          usuarioActualId={usuarioActualId}
          usuarios={usuarios}
          hilos={[]}
          hiloFijo={{ id: hiloId, titulo: hilo?.titulo ?? "" }}
          puedeAsignar={puedeAsignar}
          onClose={() => {
            setModalCrearTarea(false);
            cargar();
          }}
        />
      )}

      {modalEditarHilo && hilo && (
        <CrearHiloPanel
          hilo={hilo}
          onClose={() => {
            setModalEditarHilo(false);
            cargar();
          }}
        />
      )}

      {modalPlantilla && (
        <AgregarDesdePlantillaModal
          hiloId={hiloId}
          plantillas={plantillas}
          usuarios={usuarios}
          usuarioActualId={usuarioActualId}
          puedeAsignar={puedeAsignar}
          onAgregado={() => {
            setModalPlantilla(false);
            cargar();
          }}
          onClose={() => setModalPlantilla(false)}
        />
      )}

      {confirmarEliminar && (
        <ConfirmModal
          title="Eliminar hilo"
          message={`¿Eliminar el hilo "${hilo?.titulo}"? Esta acción no se puede deshacer.`}
          confirmLabel={eliminando ? "Eliminando..." : "Eliminar"}
          danger
          onConfirm={onEliminarHilo}
          onCancel={() => setConfirmarEliminar(false)}
        />
      )}

      {modalPosponer && (
        <PosponerModal title="Posponer hilo" onConfirm={onPosponer} onClose={() => setModalPosponer(false)} />
      )}
    </RightPanel>
  );
}

function AgregarDesdePlantillaModal({
  hiloId,
  plantillas,
  usuarios,
  usuarioActualId,
  puedeAsignar,
  onAgregado,
  onClose,
}: {
  hiloId: string;
  plantillas: TareaPlantilla[];
  usuarios: { id: string; nombre: string }[];
  usuarioActualId: string;
  puedeAsignar: boolean;
  onAgregado: () => void;
  onClose: () => void;
}) {
  const [plantillaId, setPlantillaId] = useState("");
  const [asignadoA, setAsignadoA] = useState(usuarioActualId);
  const [enviando, setEnviando] = useState(false);

  async function onAgregar() {
    if (!plantillaId) return;
    setEnviando(true);
    const result = await agregarTareasDesdePlantilla({
      hilo_id: hiloId,
      plantilla_id: plantillaId,
      asignado_a: asignadoA,
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tareas agregadas");
    onAgregado();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(7,11,20,.55)] p-4">
      <div className="w-full max-w-[400px] rounded-xl bg-bg-surface p-[30px] shadow-lg">
        <h2 className="t-h3 mb-4">Agregar desde plantilla</h2>

        <div className="flex flex-col gap-3">
          <select className="input" value={plantillaId} onChange={(e) => setPlantillaId(e.target.value)}>
            <option value="">Elegí una plantilla</option>
            {plantillas.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombre} ({p.items.length})
              </option>
            ))}
          </select>

          {puedeAsignar && (
            <select className="input" value={asignadoA} onChange={(e) => setAsignadoA(e.target.value)}>
              {usuarios.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.id === usuarioActualId ? `${u.nombre} (vos)` : u.nombre}
                </option>
              ))}
            </select>
          )}
        </div>

        <div className="mt-5 flex justify-end gap-3">
          <button className="btn btn-secondary" onClick={onClose}>
            Cancelar
          </button>
          <button className="btn btn-primary" onClick={onAgregar} disabled={!plantillaId || enviando}>
            {enviando ? "Agregando..." : "Agregar tareas"}
          </button>
        </div>
      </div>
    </div>
  );
}
