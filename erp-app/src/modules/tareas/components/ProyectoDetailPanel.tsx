"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { HiloCard } from "./HiloCard";
import { TareaRow } from "./TareaRow";
import { TareaFormPanel } from "./TareaFormPanel";
import { HiloFormPanel } from "./HiloFormPanel";
import { useOrdenTemperatura } from "../useOrdenTemperatura";

// Panel del proyecto: agregar tarea/hilo directo al proyecto + listado de lo
// que ya tiene (mismas islas — HiloCard/TareaRow — que "Mis tareas", acá sin
// filtrar por "propio": el usuario confirmó que el panel muestra todo lo
// visible del proyecto, no solo lo suyo).
export function ProyectoDetailPanel({
  proyecto,
  hilos,
  tareas,
  proyectos,
  usuarios,
  plantillas,
  usuarioActualId,
  gestionarAjenas,
  onClose,
}: {
  proyecto: TareaProyecto;
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  proyectos: TareaProyecto[];
  usuarios: Usuario[];
  plantillas: TareaPlantilla[];
  usuarioActualId: string | null;
  gestionarAjenas: boolean;
  onClose: () => void;
}) {
  const [creandoTarea, setCreandoTarea] = useState(false);
  const [creandoHilo, setCreandoHilo] = useState(false);
  const { ordenar, onTemperaturaChange } = useOrdenTemperatura();

  const hilosDelProyecto = hilos.filter((h) => h.proyecto_id === proyecto.id);
  const tareasSueltas = ordenar(tareas.filter((t) => t.proyecto_id === proyecto.id && t.hilo_id === null));

  return (
    <RightPanel title={proyecto.nombre} onClose={onClose}>
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <div className="flex flex-wrap items-center gap-2 border-b border-border p-[13px] px-5">
          <button className="btn btn-ghost btn-sm" onClick={() => setCreandoHilo(true)}>
            <Plus size={14} strokeWidth={1.75} />
            Agregar hilo
          </button>
          <button className="btn btn-ghost btn-sm" onClick={() => setCreandoTarea(true)}>
            <Plus size={14} strokeWidth={1.75} />
            Agregar tarea
          </button>
        </div>

        {hilosDelProyecto.length === 0 && tareasSueltas.length === 0 ? (
          <p className="t-caption px-5 py-3">Sin tareas ni hilos todavía.</p>
        ) : (
          <div className="flex flex-col gap-4 p-[13px] px-5">
            {hilosDelProyecto.length > 0 && (
              <div className="flex flex-col gap-3">
                <p className="t-label text-text-tertiary">Hilos</p>
                {hilosDelProyecto.map((h) => (
                  <HiloCard
                    key={h.id}
                    hilo={h}
                    tareas={tareas}
                    proyectos={proyectos}
                    usuarios={usuarios}
                    plantillas={plantillas}
                    usuarioActualId={usuarioActualId}
                    gestionarAjenas={gestionarAjenas}
                  />
                ))}
              </div>
            )}

            {tareasSueltas.length > 0 && (
              <div className="flex flex-col gap-3">
                <p className="t-label text-text-tertiary">Tareas sueltas</p>
                {tareasSueltas.map((t) => (
                  <div key={t.id} className="rounded-lg border border-border bg-bg-surface">
                    <TareaRow
                      tarea={t}
                      usuarios={usuarios}
                      hilosDisponibles={hilos}
                      usuarioActualId={usuarioActualId}
                      gestionarAjenas={gestionarAjenas}
                      onTemperaturaChange={onTemperaturaChange}
                    />
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {creandoTarea && (
        <TareaFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          usuarioActualId={usuarioActualId}
          proyectoId={proyecto.id}
          onClose={() => setCreandoTarea(false)}
        />
      )}
      {creandoHilo && (
        <HiloFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          usuarioActualId={usuarioActualId}
          proyectoId={proyecto.id}
          onClose={() => setCreandoHilo(false)}
        />
      )}
    </RightPanel>
  );
}
