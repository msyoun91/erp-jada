"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, Pencil, Plus } from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
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
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);
  const [editando, setEditando] = useState<TareaPlantilla | null>(null);
  const [desactivando, setDesactivando] = useState<TareaPlantilla | null>(null);

  async function onDesactivar(plantilla: TareaPlantilla) {
    const result = await desactivarPlantilla(plantilla.id);
    if (!result.success) toast.error(result.error);
    else toast.success("Plantilla desactivada");
  }

  const q = texto.trim().toLowerCase();
  const filtradas = plantillas.filter(
    (p) => p.nombre.toLowerCase().includes(q) || (p.descripcion ?? "").toLowerCase().includes(q),
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar plantilla…" />
        <button className="btn btn-primary" onClick={() => setCreando(true)}>
          <Plus size={16} />
          Nueva plantilla
        </button>
      </div>

      <Paginacion {...paginado} etiqueta="plantillas" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin plantillas todavía"}</p>
          <p className="t-body-m mt-1">
            {texto ? "Probá con otro término de búsqueda." : 'Creá la primera con "Nueva plantilla".'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((p) => {
            const items = itemsPorPlantilla[p.id] ?? [];
            return (
              <div key={p.id} className="border-b border-border p-[13px] px-5 last:border-b-0">
                <div className="flex items-center gap-2">
                  <div className="min-w-0 flex-1">
                    <button
                      className="tap-target t-body-m block max-w-full truncate text-left font-medium text-text-primary hover:underline"
                      onClick={() => setEditando(p)}
                      title="Modificar plantilla"
                    >
                      {p.nombre}
                    </button>
                    {p.descripcion && <p className="t-caption truncate">{p.descripcion}</p>}
                  </div>
                  <OverflowMenu
                    items={[
                      {
                        label: "Modificar",
                        icon: <Pencil size={14} strokeWidth={1.75} />,
                        onClick: () => setEditando(p),
                      },
                      {
                        label: "Desactivar",
                        icon: <Archive size={14} strokeWidth={1.75} />,
                        onClick: () => setDesactivando(p),
                        destructive: true,
                      },
                    ]}
                  />
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

      {desactivando && (
        <ConfirmModal
          title="Desactivar plantilla"
          mensaje={`¿Desactivar la plantilla "${desactivando.nombre}"?`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}

      {creando && <PlantillaFormPanel onClose={() => setCreando(false)} />}
      {editando && (
        <PlantillaFormPanel
          plantilla={editando}
          items={itemsPorPlantilla[editando.id] ?? []}
          onClose={() => setEditando(null)}
        />
      )}
    </div>
  );
}
