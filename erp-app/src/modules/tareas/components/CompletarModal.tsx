"use client";

import { useState } from "react";
import { toast } from "sonner";
import { X } from "lucide-react";
import { completarTarea } from "../actions";

export function CompletarModal({
  tareaId,
  titulo,
  onClose,
}: {
  tareaId: string;
  titulo: string;
  onClose: () => void;
}) {
  const [nota, setNota] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function confirmar() {
    setEnviando(true);
    const result = await completarTarea({
      tarea_id: tareaId,
      nota_siguiente: nota || undefined,
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea completada");
    onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(7,11,20,.55)] p-4">
      <div className="w-full max-w-[420px] rounded-xl bg-bg-surface p-[30px] shadow-lg">
        <div className="mb-5 flex items-center justify-between">
          <h2 className="t-h3">Completar tarea</h2>
          <button onClick={onClose} className="text-text-tertiary" aria-label="Cerrar">
            <X size={20} />
          </button>
        </div>

        <p className="t-body-m mb-4">{titulo}</p>

        <label className="t-label mb-1 block">Nota para la próxima (opcional)</label>
        <textarea
          rows={3}
          className="input"
          value={nota}
          onChange={(e) => setNota(e.target.value)}
        />

        <div className="mt-5 flex justify-end gap-3">
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            Cancelar
          </button>
          <button type="button" className="btn btn-primary" onClick={confirmar} disabled={enviando}>
            {enviando ? "Completando…" : "Completar"}
          </button>
        </div>
      </div>
    </div>
  );
}
