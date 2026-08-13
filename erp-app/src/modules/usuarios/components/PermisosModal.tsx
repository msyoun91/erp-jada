"use client";

import { useState } from "react";
import { toast } from "sonner";
import { X } from "lucide-react";
import { asignarSubmodulos } from "../actions";
import type { Submodulo, Usuario } from "../types";

export function PermisosModal({
  usuario,
  submodulos,
  asignados,
  onClose,
}: {
  usuario: Usuario;
  submodulos: Submodulo[];
  asignados: string[];
  onClose: () => void;
}) {
  const [seleccionados, setSeleccionados] = useState<Set<string>>(new Set(asignados));
  const [enviando, setEnviando] = useState(false);

  function toggle(id: string) {
    setSeleccionados((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function guardar() {
    setEnviando(true);
    const result = await asignarSubmodulos({
      usuario_id: usuario.id,
      submodulo_ids: [...seleccionados],
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Permisos actualizados");
    onClose();
  }

  const porModulo = Object.groupBy(submodulos, (s) => s.modulo);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(7,11,20,.55)] p-4">
      <div className="w-full max-w-[460px] rounded-xl bg-bg-surface p-[30px] shadow-lg">
        <div className="mb-5 flex items-center justify-between">
          <h2 className="t-h3">Permisos de {usuario.nombre}</h2>
          <button onClick={onClose} className="text-text-tertiary" aria-label="Cerrar">
            <X size={20} />
          </button>
        </div>

        <div className="flex max-h-[50vh] flex-col gap-4 overflow-y-auto">
          {Object.entries(porModulo).map(([modulo, items]) => (
            <div key={modulo}>
              <p className="t-label mb-2">{modulo}</p>
              <div className="flex flex-col gap-2">
                {items?.map((s) => (
                  <label key={s.id} className="flex items-center gap-2 t-body-m">
                    <input
                      type="checkbox"
                      checked={seleccionados.has(s.id)}
                      onChange={() => toggle(s.id)}
                    />
                    {s.nombre}
                  </label>
                ))}
              </div>
            </div>
          ))}
        </div>

        <div className="mt-5 flex justify-end gap-3">
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            Cancelar
          </button>
          <button className="btn btn-primary" onClick={guardar} disabled={enviando}>
            {enviando ? "Guardando..." : "Guardar"}
          </button>
        </div>
      </div>
    </div>
  );
}
