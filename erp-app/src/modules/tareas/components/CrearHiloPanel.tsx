"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { actualizarHilo, crearHilo } from "../actions";
import type { CrearHiloForm, TareaHilo } from "../types";
import { RecurrenciaFields, type RecurrenciaValue } from "./RecurrenciaFields";

export function CrearHiloPanel({
  hilo,
  onClose,
  onCreado,
}: {
  hilo?: TareaHilo | null;
  onClose: () => void;
  onCreado?: (hilo: { id: string; titulo: string }) => void;
}) {
  const [titulo, setTitulo] = useState(hilo?.titulo ?? "");
  const [descripcion, setDescripcion] = useState(hilo?.descripcion ?? "");
  const [recurrencia, setRecurrencia] = useState<RecurrenciaValue>({
    recurrencia_activa: hilo?.recurrencia_activa ?? false,
    recurrencia_una_vez: hilo?.recurrencia_una_vez ?? false,
    recurrencia_intervalo: hilo?.recurrencia_intervalo ?? "mes",
    recurrencia_cada: hilo?.recurrencia_cada ?? 1,
    recurrencia_proxima: hilo?.recurrencia_proxima ?? "",
  });
  const [enviando, setEnviando] = useState(false);

  async function onSubmit(seguirConTarea = false) {
    if (!titulo.trim()) {
      toast.error("El título es obligatorio");
      return;
    }
    if (recurrencia.recurrencia_activa && !recurrencia.recurrencia_proxima) {
      toast.error("Elegí la próxima fecha de repetición");
      return;
    }

    setEnviando(true);
    const data: CrearHiloForm = { titulo, descripcion, ...recurrencia };

    if (hilo) {
      const result = await actualizarHilo(hilo.id, data);
      setEnviando(false);
      if (!result.success) {
        toast.error(result.error);
        return;
      }
      toast.success("Hilo actualizado");
      onClose();
      return;
    }

    const result = await crearHilo(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo creado");
    if (seguirConTarea) onCreado?.({ id: result.hilo_id, titulo });
    else onClose();
  }

  return (
    <RightPanel
      title={hilo ? "Editar hilo" : "Nuevo hilo"}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            Cancelar
          </button>
          {!hilo && onCreado && (
            <button
              type="button"
              className="btn btn-secondary"
              onClick={() => onSubmit(true)}
              disabled={enviando}
            >
              Crear y agregar tarea
            </button>
          )}
          <button type="button" className="btn btn-primary" onClick={() => onSubmit()} disabled={enviando}>
            {enviando ? "Guardando..." : hilo ? "Guardar" : "Crear hilo"}
          </button>
        </>
      }
    >
      <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <div>
          <label className="t-label mb-1 block">Título</label>
          <input className="input" value={titulo} onChange={(e) => setTitulo(e.target.value)} />
        </div>

        <div>
          <label className="t-label mb-1 block">Descripción</label>
          <textarea
            className="input"
            rows={3}
            value={descripcion}
            onChange={(e) => setDescripcion(e.target.value)}
          />
        </div>

        <div className="border-t border-border pt-4">
          <p className="t-label mb-2">Recurrencia</p>
          <RecurrenciaFields value={recurrencia} onChange={setRecurrencia} />
        </div>
      </div>
    </RightPanel>
  );
}
