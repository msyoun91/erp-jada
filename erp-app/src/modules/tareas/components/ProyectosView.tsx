"use client";

import { useState } from "react";
import { toast } from "sonner";
import { FolderPlus, ListTodo, Users } from "lucide-react";
import { desactivarProyecto } from "../actions";
import type { ProyectoMiembro, TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
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
  miembrosPorProyecto: Record<string, ProyectoMiembro[]>;
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  puedeCrear: boolean;
}) {
  const [creando, setCreando] = useState(false);
  const [miembrosDe, setMiembrosDe] = useState<TareaProyecto | null>(null);
  const [detalleDe, setDetalleDe] = useState<TareaProyecto | null>(null);

  async function onDesactivar(proyecto: TareaProyecto) {
    if (!confirm(`¿Desactivar proyecto "${proyecto.nombre}"?`)) return;
    const result = await desactivarProyecto(proyecto.id);
    if (!result.success) toast.error(result.error);
  }

  return (
    <div>
      {puedeCrear && (
        <div className="mb-4 flex justify-end">
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <FolderPlus size={16} />
            Nuevo proyecto
          </button>
        </div>
      )}

      {proyectos.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin proyectos todavía</p>
          <p className="t-body-m mt-1">Creá el primero con &quot;Nuevo proyecto&quot;.</p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {proyectos.map((p) => {
            const puedeGestionar = gestionarAjenas || p.creado_por === usuarioActualId;
            return (
              <div
                key={p.id}
                className="flex items-center justify-between border-b border-border p-[13px] px-5 last:border-b-0"
              >
                <div>
                  <p className="t-body-m font-medium text-text-primary">{p.nombre}</p>
                  {p.descripcion && <p className="t-caption">{p.descripcion}</p>}
                </div>

                <div className="flex items-center gap-2">
                  <span className={`badge ${p.visibilidad === "privado" ? "badge-warning" : "badge-neutral"}`}>
                    {p.visibilidad === "privado" ? "Privado" : "Público"}
                  </span>

                  <button className="btn btn-ghost btn-sm" onClick={() => setDetalleDe(p)}>
                    <ListTodo size={14} strokeWidth={1.75} />
                    Ver tareas
                  </button>

                  {puedeGestionar && p.visibilidad === "privado" && (
                    <button className="btn btn-ghost btn-sm" onClick={() => setMiembrosDe(p)}>
                      <Users size={14} strokeWidth={1.75} />
                      Miembros
                    </button>
                  )}
                  {puedeGestionar && (
                    <button className="btn btn-ghost btn-sm text-error" onClick={() => onDesactivar(p)}>
                      Desactivar
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {creando && <ProyectoFormPanel usuarios={usuarios} onClose={() => setCreando(false)} />}

      {miembrosDe && (
        <MiembrosPanel
          proyecto={miembrosDe}
          usuarios={usuarios}
          miembrosActuales={(miembrosPorProyecto[miembrosDe.id] ?? []).map((m) => m.usuario_id)}
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
          usuarioActualId={usuarioActualId}
          gestionarAjenas={gestionarAjenas}
          onClose={() => setDetalleDe(null)}
        />
      )}
    </div>
  );
}
