"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, FolderPlus, ListTodo, Users } from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { desactivarProyecto } from "../actions";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { ProyectoFormPanel } from "./ProyectoFormPanel";
import { MiembrosPanel } from "./MiembrosPanel";
import { ProyectoDetailPanel } from "./ProyectoDetailPanel";

export function ProyectosView({
  proyectos,
  hilos,
  tareas,
  usuarios,
  plantillas,
  miembrosPorProyecto,
  usuarioActualId,
  gestionarAjenas,
  puedeCrear,
}: {
  proyectos: TareaProyecto[];
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  usuarios: Usuario[];
  plantillas: TareaPlantilla[];
  miembrosPorProyecto: Record<string, string[]>;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  puedeCrear: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [creando, setCreando] = useState(false);
  const [miembrosDe, setMiembrosDe] = useState<TareaProyecto | null>(null);
  const [detalleDe, setDetalleDe] = useState<TareaProyecto | null>(null);
  const [desactivando, setDesactivando] = useState<TareaProyecto | null>(null);

  async function onDesactivar(proyecto: TareaProyecto) {
    const result = await desactivarProyecto(proyecto.id);
    if (!result.success) toast.error(result.error);
  }

  const q = texto.trim().toLowerCase();
  const filtrados = proyectos.filter(
    (p) => p.nombre.toLowerCase().includes(q) || (p.descripcion ?? "").toLowerCase().includes(q),
  );
  const { visibles, ...paginado } = usePaginado(filtrados);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar proyecto…" />
        {puedeCrear && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <FolderPlus size={16} />
            Nuevo proyecto
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="proyectos" />

      {filtrados.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin proyectos todavía"}</p>
          <p className="t-body-m mt-1">
            {texto ? "Probá con otro término de búsqueda." : 'Creá el primero con "Nuevo proyecto".'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((p) => {
            const puedeGestionar = gestionarAjenas || p.creado_por === usuarioActualId;
            return (
              <div
                key={p.id}
                className="flex items-center gap-2 border-b border-border p-[13px] px-5 last:border-b-0"
              >
                <div className="min-w-0 flex-1">
                  <button
                    className="t-body-m block max-w-full truncate text-left font-medium text-text-primary hover:underline"
                    onClick={() => setDetalleDe(p)}
                    title="Ver tareas"
                  >
                    {p.nombre}
                  </button>
                  {p.descripcion && <p className="t-caption truncate">{p.descripcion}</p>}
                </div>

                <span
                  className={`badge shrink-0 ${p.visibilidad === "privado" ? "badge-warning" : "badge-neutral"}`}
                >
                  {p.visibilidad === "privado" ? "Privado" : "Público"}
                </span>

                <OverflowMenu
                  items={[
                    {
                      label: "Ver tareas",
                      icon: <ListTodo size={14} strokeWidth={1.75} />,
                      onClick: () => setDetalleDe(p),
                    },
                    ...(puedeGestionar
                      ? [
                          {
                            label: "Miembros",
                            icon: <Users size={14} strokeWidth={1.75} />,
                            onClick: () => setMiembrosDe(p),
                          },
                          {
                            label: "Desactivar",
                            icon: <Archive size={14} strokeWidth={1.75} />,
                            onClick: () => setDesactivando(p),
                            destructive: true,
                          },
                        ]
                      : []),
                  ]}
                />
              </div>
            );
          })}
        </div>
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar proyecto"
          mensaje={`¿Desactivar el proyecto "${desactivando.nombre}"?`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}

      {creando && (
        <ProyectoFormPanel
          usuarios={usuarios}
          usuarioActualId={usuarioActualId}
          onClose={() => setCreando(false)}
        />
      )}

      {miembrosDe && (
        <MiembrosPanel
          proyecto={miembrosDe}
          usuarios={usuarios}
          miembrosActuales={miembrosPorProyecto[miembrosDe.id] ?? []}
          onClose={() => setMiembrosDe(null)}
        />
      )}

      {detalleDe && (
        <ProyectoDetailPanel
          proyecto={detalleDe}
          hilos={hilos}
          tareas={tareas}
          proyectos={proyectos}
          usuarios={usuarios}
          plantillas={plantillas}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          gestionarAjenas={gestionarAjenas}
          onClose={() => setDetalleDe(null)}
        />
      )}
    </div>
  );
}
