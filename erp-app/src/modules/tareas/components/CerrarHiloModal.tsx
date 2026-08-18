"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Modal } from "@/components/ui/Modal";
import { CheckCircle2 } from "lucide-react";
import { cerrarHilo } from "../actions";
import type { TareaConAsignados } from "../types";

export function CerrarHiloModal({
  hiloId,
  hiloTitulo,
  tareas,
  onClose,
  onMantenerAbierto,
}: {
  hiloId: string;
  hiloTitulo: string;
  tareas: TareaConAsignados[];
  onClose: () => void;
  onMantenerAbierto: () => void;
}) {
  const [enviando, setEnviando] = useState(false);

  async function confirmar() {
    setEnviando(true);
    const result = await cerrarHilo({ hilo_id: hiloId });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo cerrado");
    onClose();
  }

  return (
    <Modal title="¿Cerrar hilo?" onClose={onMantenerAbierto} maxWidth={440}>
      <p className="t-body-m mb-4">
        Todas las tareas de &quot;{hiloTitulo}&quot; están completadas o canceladas.
      </p>

      <div className="mb-5 flex flex-col rounded-lg border border-border">
        {tareas.map((t) => (
          <div key={t.id} className="flex items-center gap-2 border-b border-border p-2.5 px-3 last:border-b-0">
            <CheckCircle2 size={15} strokeWidth={1.75} className="shrink-0 text-success" />
            <span className="t-body-m">{t.titulo}</span>
          </div>
        ))}
      </div>

      <div className="flex justify-end gap-3">
        <button type="button" className="btn btn-secondary" onClick={onMantenerAbierto} disabled={enviando}>
          Mantener abierto
        </button>
        <button type="button" className="btn btn-primary" onClick={confirmar} disabled={enviando}>
          {enviando ? "Cerrando…" : "Cerrar hilo"}
        </button>
      </div>
    </Modal>
  );
}
