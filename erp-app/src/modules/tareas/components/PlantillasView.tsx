"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Plus, Pencil } from "lucide-react";
import { ConfirmModal } from "@/components/ui/ConfirmModal";
import { desactivarPlantilla } from "../actions";
import type { TareaPlantilla } from "../types";
import { PlantillaPanel } from "./PlantillaPanel";

export function PlantillasView({ plantillas }: { plantillas: TareaPlantilla[] }) {
  const [modalCrear, setModalCrear] = useState(false);
  const [plantillaEditar, setPlantillaEditar] = useState<TareaPlantilla | null>(null);
  const [plantillaDesactivar, setPlantillaDesactivar] = useState<TareaPlantilla | null>(null);

  async function onDesactivar() {
    if (!plantillaDesactivar) return;
    const result = await desactivarPlantilla(plantillaDesactivar.id);
    setPlantillaDesactivar(null);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Plantilla desactivada");
  }

  return (
    <div>
      <div className="mb-4 flex justify-end">
        <button className="btn btn-primary" onClick={() => setModalCrear(true)}>
          <Plus size={16} />
          Nueva plantilla
        </button>
      </div>

      <p className="t-caption mb-2">{plantillas.length} plantillas</p>

      {plantillas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin plantillas todavía</p>
          <p className="t-body-m mt-1">Creá la primera con &quot;Nueva plantilla&quot;.</p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {plantillas.map((plantilla) => (
            <div
              key={plantilla.id}
              className="flex items-center justify-between border-b border-border p-[13px] px-5 last:border-b-0"
            >
              <div>
                <p className="t-body-m font-medium text-text-primary">{plantilla.nombre}</p>
                <p className="t-caption">{plantilla.items.length} tareas</p>
              </div>

              <div className="flex items-center gap-2">
                <button className="btn btn-ghost btn-sm" onClick={() => setPlantillaEditar(plantilla)}>
                  <Pencil size={14} />
                  Editar
                </button>
                <button className="btn btn-ghost btn-sm text-error" onClick={() => setPlantillaDesactivar(plantilla)}>
                  Desactivar
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {modalCrear && <PlantillaPanel plantilla={null} onClose={() => setModalCrear(false)} />}

      {plantillaEditar && <PlantillaPanel plantilla={plantillaEditar} onClose={() => setPlantillaEditar(null)} />}

      {plantillaDesactivar && (
        <ConfirmModal
          title="Desactivar plantilla"
          message={`¿Desactivar la plantilla "${plantillaDesactivar.nombre}"?`}
          confirmLabel="Desactivar"
          danger
          onConfirm={onDesactivar}
          onCancel={() => setPlantillaDesactivar(null)}
        />
      )}
    </div>
  );
}
