"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearHilo } from "../actions";

export function CrearHiloPanel({ onClose }: { onClose: () => void }) {
  const [titulo, setTitulo] = useState("");
  const [enviando, setEnviando] = useState(false);

  async function onSubmit() {
    if (!titulo.trim()) {
      toast.error("El título es obligatorio");
      return;
    }

    setEnviando(true);
    const result = await crearHilo({ titulo });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo creado");
    onClose();
  }

  return (
    <RightPanel
      title="Nuevo hilo"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            Cancelar
          </button>
          <button type="button" className="btn btn-primary" onClick={onSubmit} disabled={enviando}>
            {enviando ? "Creando..." : "Crear hilo"}
          </button>
        </>
      }
    >
      <div className="flex min-h-0 flex-1 flex-col gap-4 px-5 py-4">
        <div>
          <label className="t-label mb-1 block">Título</label>
          <input className="input" value={titulo} onChange={(e) => setTitulo(e.target.value)} />
        </div>
      </div>
    </RightPanel>
  );
}
