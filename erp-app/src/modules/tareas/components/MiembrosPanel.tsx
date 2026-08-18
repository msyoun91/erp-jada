"use client";

import { useState } from "react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { gestionarMiembrosProyecto } from "../actions";
import type { TareaProyecto, Usuario } from "../types";

export function MiembrosPanel({
  proyecto,
  usuarios,
  miembrosActuales,
  onClose,
}: {
  proyecto: TareaProyecto;
  usuarios: Usuario[];
  miembrosActuales: string[];
  onClose: () => void;
}) {
  const [seleccionados, setSeleccionados] = useState<string[]>(miembrosActuales);
  const [enviando, setEnviando] = useState(false);

  function toggle(id: string) {
    setSeleccionados((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  async function guardar() {
    setEnviando(true);
    const result = await gestionarMiembrosProyecto(proyecto.id, seleccionados);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Miembros actualizados");
    onClose();
  }

  return (
    <RightPanel
      title="Miembros"
      subtitle={proyecto.nombre}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button className="btn btn-primary btn-sm" onClick={guardar} disabled={enviando}>
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      <div className="flex-1 overflow-y-auto px-5 py-4">
        {usuarios.map((u) => (
          <label key={u.id} className="flex cursor-pointer items-center gap-2 py-2 hover:bg-bg-subtle">
            <input
              type="checkbox"
              checked={seleccionados.includes(u.id)}
              onChange={() => toggle(u.id)}
              className="h-4 w-4 shrink-0 accent-brand-700"
            />
            <span className="t-body-m">{u.nombre}</span>
          </label>
        ))}
      </div>
    </RightPanel>
  );
}
