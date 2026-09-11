"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, Pencil, Plus } from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { desactivarPlantilla } from "../actions";
import type { PlantillaCompleta, TipoPlantilla } from "../types";
import { PlantillaFormPanel } from "./PlantillaFormPanel";
import { UsarPlantillaPanel } from "./UsarPlantillaPanel";
import { useTareasContexto } from "./tareasContexto";

const TIPO_LABEL: Record<TipoPlantilla, string> = { tarea: "Tarea", hilo: "Hilo", proyecto: "Proyecto" };

export function PlantillasView({
  plantillas,
  puedeSistema,
  puedeCrearProyecto,
}: {
  plantillas: PlantillaCompleta[];
  puedeSistema: boolean;
  puedeCrearProyecto: boolean;
}) {
  const { usuarioActualId } = useTareasContexto();
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);
  const [editando, setEditando] = useState<PlantillaCompleta | null>(null);
  const [usando, setUsando] = useState<PlantillaCompleta | null>(null);
  const [desactivando, setDesactivando] = useState<PlantillaCompleta | null>(null);

  // Espejo de `puede_gestionar_plantilla` (sql/053): ofrecer lo que la RLS
  // después rechaza sería mentir. La barrera sigue siendo la base.
  const puedeGestionar = (p: PlantillaCompleta) =>
    p.alcance === "sistema" ? puedeSistema : p.creado_por === usuarioActualId;

  async function onDesactivar(plantilla: PlantillaCompleta) {
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
        <button data-tour="tareas_plantillas_crear" className="btn btn-primary" onClick={() => setCreando(true)}>
          <Plus size={16} />
          Nueva plantilla
        </button>
      </div>

      <Paginacion {...paginado} etiqueta="plantillas" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin plantillas todavía"}</p>
          <p className="t-body-m mt-1">
            {texto ? "Probá con otro término de búsqueda." : "Creá la primera con «Nueva plantilla»."}
          </p>
        </div>
      ) : (
        <div data-tour="tareas_plantillas_lista" className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((p) => {
            const sinPermisoProyecto = p.tipo === "proyecto" && !puedeCrearProyecto;
            return (
              <div key={p.id} className="border-b border-border row last:border-b-0">
                <div className="flex items-center gap-2">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="t-body-m truncate font-medium text-text-primary">{p.nombre}</p>
                      <span className={`badge shrink-0 ${p.alcance === "sistema" ? "badge-info" : "badge-neutral"}`}>
                        {p.alcance === "sistema" ? "De sistema" : "Privada"}
                      </span>
                      <span className="t-caption shrink-0">{TIPO_LABEL[p.tipo]}</span>
                    </div>
                    {p.descripcion && <p className="t-caption truncate">{p.descripcion}</p>}
                  </div>
                  <button
                    className="btn btn-secondary btn-sm shrink-0"
                    onClick={() => setUsando(p)}
                    disabled={sinPermisoProyecto}
                  >
                    Usar
                  </button>
                  {puedeGestionar(p) && (
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
                  )}
                </div>
                <Contenido plantilla={p} />
                {sinPermisoProyecto && (
                  <p className="t-caption mt-1">Usarla crea un proyecto: necesitás el permiso «Crear proyectos».</p>
                )}
              </div>
            );
          })}
        </div>
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar plantilla"
          mensaje={`¿Desactivar la plantilla "${desactivando.nombre}"? Lo que ya se creó con ella no se toca.`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}

      {creando && <PlantillaFormPanel puedeSistema={puedeSistema} onClose={() => setCreando(false)} />}
      {editando && (
        <PlantillaFormPanel plantilla={editando} puedeSistema={puedeSistema} onClose={() => setEditando(null)} />
      )}
      {usando && (
        <UsarPlantillaPanel
          plantillas={plantillas.filter((p) => p.tipo !== "proyecto" || puedeCrearProyecto)}
          plantillaId={usando.id}
          onClose={() => setUsando(null)}
        />
      )}
    </div>
  );
}

// Qué tiene adentro, en una línea por hilo: la plantilla se elige por su
// contenido, no por el nombre.
function Contenido({ plantilla }: { plantilla: PlantillaCompleta }) {
  const sueltas = plantilla.items.filter((i) => !i.hilo_id);

  if (plantilla.tipo === "proyecto") {
    return (
      <ul className="t-caption mt-2 flex list-disc flex-col gap-1 pl-4">
        {plantilla.hilos.map((h) => (
          <li key={h.id}>
            Hilo «{h.titulo}»: {plantilla.items.filter((i) => i.hilo_id === h.id).map((i) => i.titulo).join(" → ")}
          </li>
        ))}
        {sueltas.length > 0 && <li>Sueltas: {sueltas.map((i) => i.titulo).join(", ")}</li>}
      </ul>
    );
  }

  return (
    <p className="t-caption mt-2">
      {plantilla.tipo === "hilo" ? sueltas.map((i) => i.titulo).join(" → ") : sueltas[0]?.titulo}
    </p>
  );
}
