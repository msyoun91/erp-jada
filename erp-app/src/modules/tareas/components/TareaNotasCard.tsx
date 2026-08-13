"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Clock, Trash2 } from "lucide-react";
import { ConfirmModal } from "@/components/ui/ConfirmModal";
import { PosponerModal } from "@/components/ui/PosponerModal";
import {
  agregarNota,
  actualizarEstadoTarea,
  desactivarTarea,
  desasociarTareaHilo,
  posponerTarea,
  quitarPosposicionTarea,
  reasignarTarea,
} from "../actions";
import type { EstadoTarea, TareaConRelaciones, TareaNota } from "../types";
import { ESTADO_ICON, ESTADO_ICON_COLOR, ESTADO_LABEL, formatPosponer, formatVencimiento } from "./estado";

export function TareaNotasCard({
  tarea,
  notas,
  usuarios,
  puedeAsignar,
  onCambio,
  onEliminado,
  ocultarTitulo,
}: {
  tarea: TareaConRelaciones;
  notas: TareaNota[];
  usuarios: { id: string; nombre: string }[];
  puedeAsignar: boolean;
  onCambio: () => void;
  onEliminado?: () => void;
  // El panel de detalle ya muestra el título en su encabezado
  ocultarTitulo?: boolean;
}) {
  const [nota, setNota] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [confirmarEliminar, setConfirmarEliminar] = useState(false);
  const [modalPosponer, setModalPosponer] = useState(false);

  async function onCambiarEstado(estado: EstadoTarea) {
    const result = await actualizarEstadoTarea({ tarea_id: tarea.id, estado });
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    onCambio();
  }

  async function onReasignar(asignado_a: string) {
    const result = await reasignarTarea({ tarea_id: tarea.id, asignado_a });
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea reasignada");
    onCambio();
  }

  async function onAgregarNota() {
    if (!nota.trim() || enviando) return;
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

  async function onPosponer(fecha: string) {
    const result = await posponerTarea({ tarea_id: tarea.id, posponer_hasta: fecha });
    setModalPosponer(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea pospuesta");
    onCambio();
  }

  async function onQuitarPosposicion() {
    const result = await quitarPosposicionTarea(tarea.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    onCambio();
  }

  const vencimiento = formatVencimiento(tarea);
  const IconoEstado = ESTADO_ICON[tarea.estado];

  return (
    <div className="rounded-lg border border-border p-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          {!ocultarTitulo && (
            <p className="t-body-m flex items-center gap-2 font-medium text-text-primary">
              <IconoEstado
                size={16}
                strokeWidth={1.75}
                className={`shrink-0 ${ESTADO_ICON_COLOR[tarea.estado]}`}
                aria-label={ESTADO_LABEL[tarea.estado]}
              />
              {tarea.titulo}
            </p>
          )}
          {tarea.descripcion && <p className="t-caption whitespace-pre-line">{tarea.descripcion}</p>}
          <p className="t-caption">
            {puedeAsignar ? (
              <select
                className="input !w-auto py-0.5 text-[12px]"
                aria-label="Asignar tarea a"
                value={tarea.asignado_a}
                onChange={(e) => onReasignar(e.target.value)}
              >
                {usuarios.map((u) => (
                  <option key={u.id} value={u.id}>
                    {u.nombre}
                  </option>
                ))}
              </select>
            ) : (
              tarea.asignado_a_nombre
            )}
            {tarea.hilo_id && (
              <>
                {" · "}
                <button type="button" className="text-text-brand" onClick={onDesasociar}>
                  Quitar del hilo
                </button>
              </>
            )}
            {tarea.posponer_hasta && (
              <>
                {" · "}
                {formatPosponer(tarea)}
                {" · "}
                <button type="button" className="text-text-brand" onClick={onQuitarPosposicion}>
                  Quitar posposición
                </button>
              </>
            )}
          </p>
        </div>
        <div className="flex shrink-0 flex-wrap items-center justify-end gap-2">
          {vencimiento && <span className={`badge ${vencimiento.badge}`}>{vencimiento.texto}</span>}
          <select
            className="input !w-auto py-1 text-[12px]"
            aria-label="Estado de la tarea"
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
            className="text-text-tertiary hover:text-text-brand"
            onClick={() => setModalPosponer(true)}
            aria-label="Posponer tarea"
          >
            <Clock size={16} />
          </button>
          <button
            className="border-l border-border pl-2 text-text-tertiary hover:text-error"
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
          disabled={enviando}
          aria-label="Agregar nota"
          onChange={(e) => setNota(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && onAgregarNota()}
        />
        <button className="btn btn-secondary btn-sm" onClick={onAgregarNota} disabled={enviando || !nota.trim()}>
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

      {modalPosponer && (
        <PosponerModal title="Posponer tarea" onConfirm={onPosponer} onClose={() => setModalPosponer(false)} />
      )}
    </div>
  );
}
