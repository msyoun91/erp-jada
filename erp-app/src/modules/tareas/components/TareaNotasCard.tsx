"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { ConfirmModal } from "@/components/ui/ConfirmModal";
import { agregarNota, actualizarEstadoTarea, desactivarTarea, desasociarTareaHilo } from "../actions";
import type { EstadoTarea, TareaConRelaciones, TareaNota } from "../types";
import { ESTADO_LABEL } from "./estado";

export function TareaNotasCard({
  tarea,
  notas,
  onCambio,
  onEliminado,
}: {
  tarea: TareaConRelaciones;
  notas: TareaNota[];
  onCambio: () => void;
  onEliminado?: () => void;
}) {
  const [nota, setNota] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [confirmarEliminar, setConfirmarEliminar] = useState(false);

  async function onCambiarEstado(estado: EstadoTarea) {
    const result = await actualizarEstadoTarea({ tarea_id: tarea.id, estado });
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    onCambio();
  }

  async function onAgregarNota() {
    if (!nota.trim()) return;
    setEnviando(true);
    const result = await agregarNota({ tarea_id: tarea.id, nota });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    setNota("");
    onCambio();
  }

  async function onEliminar() {
    setConfirmarEliminar(false);
    const result = await desactivarTarea(tarea.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    (onEliminado ?? onCambio)();
  }

  async function onDesasociar() {
    const result = await desasociarTareaHilo(tarea.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    (onEliminado ?? onCambio)();
  }

  return (
    <div className="rounded-lg border border-border p-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="t-body-m font-medium text-text-primary">{tarea.titulo}</p>
          <p className="t-caption">
            {tarea.asignado_a_nombre}
            {tarea.hilo_id && (
              <>
                {" · "}
                <button type="button" className="text-text-brand" onClick={onDesasociar}>
                  Quitar del hilo
                </button>
              </>
            )}
          </p>
        </div>
        <div className="flex items-center gap-1">
          <select
            className="input !w-auto py-1 text-[12px]"
            value={tarea.estado}
            onChange={(e) => onCambiarEstado(e.target.value as EstadoTarea)}
          >
            {Object.entries(ESTADO_LABEL).map(([valor, label]) => (
              <option key={valor} value={valor}>
                {label}
              </option>
            ))}
          </select>
          <button
            className="text-text-tertiary hover:text-error"
            onClick={() => setConfirmarEliminar(true)}
            aria-label="Eliminar tarea"
          >
            <Trash2 size={16} />
          </button>
        </div>
      </div>

      {notas.length > 0 && (
        <div className="mt-3 flex flex-col gap-2 border-t border-border pt-2">
          {notas.map((n) => (
            <div key={n.id} className="text-[13px]">
              <span className="font-medium text-text-primary">{n.usuario_nombre}: </span>
              <span className="text-text-secondary">{n.nota}</span>
            </div>
          ))}
        </div>
      )}

      <div className="mt-2 flex gap-2">
        <input
          className="input py-1 text-[13px]"
          placeholder="Agregar nota..."
          value={nota}
          onChange={(e) => setNota(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && onAgregarNota()}
        />
        <button className="btn btn-secondary btn-sm" onClick={onAgregarNota} disabled={enviando}>
          Agregar
        </button>
      </div>

      {confirmarEliminar && (
        <ConfirmModal
          title="Eliminar tarea"
          message={`¿Eliminar "${tarea.titulo}"?`}
          confirmLabel="Eliminar"
          danger
          onConfirm={onEliminar}
          onCancel={() => setConfirmarEliminar(false)}
        />
      )}
    </div>
  );
}
