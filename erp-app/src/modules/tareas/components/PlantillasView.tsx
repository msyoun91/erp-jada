"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Plus } from "lucide-react";
import { desactivarPlantilla } from "../actions";
import type { TareaPlantilla, TareaPlantillaItem } from "../types";
import { PlantillaFormPanel } from "./PlantillaFormPanel";

export function PlantillasView({
  plantillas,
  itemsPorPlantilla,
}: {
  plantillas: TareaPlantilla[];
  itemsPorPlantilla: Record<string, TareaPlantillaItem[]>;
}) {
  const [creando, setCreando] = useState(false);

  async function onDesactivar(plantilla: TareaPlantilla) {
    if (!confirm(`¿Desactivar plantilla "${plantilla.nombre}"?`)) return;
    const result = await desactivarPlantilla(plantilla.id);
    if (!result.success) toast.error(result.error);
  }

  return (
    <div>
      <div className="mb-4 flex justify-end">
        <button className="btn btn-primary" onClick={() => setCreando(true)}>
          <Plus size={16} />
          Nueva plantilla
        </button>
      </div>

      {plantillas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin plantillas todavía</p>
          <p className="t-body-m mt-1">Creá la primera con &quot;Nueva plantilla&quot;.</p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {plantillas.map((p) => {
            const items = itemsPorPlantilla[p.id] ?? [];
            return (
              <div key={p.id} className="border-b border-border p-[13px] px-5 last:border-b-0">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="t-body-m font-medium text-text-primary">{p.nombre}</p>
                    {p.descripcion && <p className="t-caption">{p.descripcion}</p>}
                  </div>
                  <button className="btn btn-ghost btn-sm text-error" onClick={() => onDesactivar(p)}>
                    Desactivar
                  </button>
                </div>
                <ul className="mt-2 flex flex-col gap-1 pl-4 t-caption list-disc">
                  {items.map((item) => (
                    <li key={item.id}>{item.titulo}</li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>
      )}

      {creando && <PlantillaFormPanel onClose={() => setCreando(false)} />}
    </div>
  );
}
