"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Modal } from "@/components/ui/Modal";
import { AlertTriangle } from "lucide-react";
import { deshacerConversionHilo } from "../actions";
import type { TareaConAsignados } from "../types";
import { ESTADO_LABEL } from "./tareaLabels";

export function DeshacerConversionModal({
  hiloId,
  hiloTitulo,
  tareas,
  onClose,
}: {
  hiloId: string;
  hiloTitulo: string;
  tareas: TareaConAsignados[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);

  // Mismo criterio que el server: la tarea más antigua del hilo es la que
  // sobrevive como tarea suelta; el resto se desactiva.
  const ordenadas = [...tareas].sort(
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  );
  const [primera, ...resto] = ordenadas;
  const hayPerdida = resto.length > 0 || tareas.some((t) => t.estado === "completada");

  async function confirmar() {
    setEnviando(true);
    const result = await deshacerConversionHilo({ hilo_id: hiloId });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Conversión deshecha");
    onClose();
  }

  return (
    <Modal title="Deshacer conversión" onClose={onClose} maxWidth={460}>
      <p className="t-body-m mb-4">
        &quot;{hiloTitulo}&quot; vuelve a ser una tarea suelta.
      </p>

      {hayPerdida && (
        <div className="mb-4 flex items-start gap-2 rounded-lg bg-warning-bg p-3 text-warning-text">
          <AlertTriangle size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
          <p className="t-caption">
            Este hilo tiene más de un paso o alguno ya completado. Se conserva solo el más antiguo — el
            resto queda desactivado (no se pierde, pero sale de las listas).
          </p>
        </div>
      )}

      <div className="mb-5 flex flex-col rounded-lg border border-border">
        {primera && (
          <div className="flex items-center justify-between border-b border-border p-2.5 px-3 last:border-b-0">
            <span className="t-body-m">{primera.titulo}</span>
            <span className="badge badge-success">Se conserva</span>
          </div>
        )}
        {resto.map((t) => (
          <div key={t.id} className="flex items-center justify-between border-b border-border p-2.5 px-3 last:border-b-0">
            <span className="t-body-m">{t.titulo}</span>
            <span className="badge badge-neutral">Se desactiva · {ESTADO_LABEL[t.estado]}</span>
          </div>
        ))}
      </div>

      <div className="flex justify-end gap-3">
        <button type="button" className="btn btn-secondary" onClick={onClose}>
          Cancelar
        </button>
        <button type="button" className="btn btn-primary" onClick={confirmar} disabled={enviando}>
          {enviando ? "Deshaciendo…" : "Deshacer conversión"}
        </button>
      </div>
    </Modal>
  );
}
