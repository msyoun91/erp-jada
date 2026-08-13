"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { ConfirmModal } from "@/components/ui/ConfirmModal";
import { agregarTareasDesdePlantilla, desactivarHilo, obtenerHistorialHilo, obtenerPlantillas } from "../actions";
import type { TareaConRelaciones, TareaHilo, TareaNota, TareaPlantilla } from "../types";
import { HILO_ESTADO_BADGE, HILO_ESTADO_LABEL } from "./estado";
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
  const [confirmarEliminar, setConfirmarEliminar] = useState(false);
  const [eliminando, setEliminando] = useState(false);

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

  return (
    <RightPanel
      title={hilo?.titulo ?? "Historial del hilo"}
      subtitle={hilo ? HILO_ESTADO_LABEL[hilo.estado] : undefined}
      onClose={onClose}
    >
      <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
        {cargando ? (
          <p className="t-caption">Cargando...</p>
        ) : (
          <>
            <div className="mb-3 flex items-center justify-between">
              {hilo && (
                <span className={`badge ${HILO_ESTADO_BADGE[hilo.estado]}`}>{HILO_ESTADO_LABEL[hilo.estado]}</span>
              )}
              <div className="flex items-center gap-2">
                {puedeCrear && (
                  <button className="btn btn-secondary btn-sm" onClick={() => setModalCrearTarea(true)}>
                    <Plus size={14} />
                    Nueva tarea
                  </button>
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

            {puedeCrear && plantillas.length > 0 && (
              <AgregarDesdePlantilla
                hiloId={hiloId}
                plantillas={plantillas}
                usuarios={usuarios}
                usuarioActualId={usuarioActualId}
                puedeAsignar={puedeAsignar}
                onAgregado={cargar}
              />
            )}

            {tareas.length === 0 ? (
              <div className="empty-state">Sin tareas en este hilo todavía.</div>
            ) : (
              <div className="flex flex-col gap-3">
                {tareas.map((tarea) => (
                  <TareaNotasCard
                    key={tarea.id}
                    tarea={tarea}
                    notas={notas.filter((n) => n.tarea_id === tarea.id)}
                    onCambio={cargar}
                  />
                ))}
              </div>
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
    </RightPanel>
  );
}

function AgregarDesdePlantilla({
  hiloId,
  plantillas,
  usuarios,
  usuarioActualId,
  puedeAsignar,
  onAgregado,
}: {
  hiloId: string;
  plantillas: TareaPlantilla[];
  usuarios: { id: string; nombre: string }[];
  usuarioActualId: string;
  puedeAsignar: boolean;
  onAgregado: () => void;
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
    setPlantillaId("");
    onAgregado();
  }

  return (
    <div className="mb-4 flex flex-col gap-2 rounded-lg border border-dashed border-border-strong p-3">
      <p className="t-label">Agregar desde plantilla</p>
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

      <button className="btn btn-secondary btn-sm" onClick={onAgregar} disabled={!plantillaId || enviando}>
        {enviando ? "Agregando..." : "Agregar tareas"}
      </button>
    </div>
  );
}
