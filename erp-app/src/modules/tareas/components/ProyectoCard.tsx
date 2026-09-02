"use client";

import { useState } from "react";
import { Users } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto } from "../types";
import { Isla } from "./Isla";
import { MetricasResumen, contarTerminadas } from "./MetricasResumen";
import { ProyectoDetailPanel } from "./ProyectoDetailPanel";
import { tareasDeProyecto } from "./proyectoTareas";
import { useTareasContexto } from "./tareasContexto";

// Isla resumen del proyecto: misma cara que HiloCard y TareaCard. Las
// acciones (modificar, desactivar, agregar) viven en ProyectoDetailPanel.
export function ProyectoCard({
  proyecto,
  hilos,
  tareas,
  plantillas,
  gestionarMiembros,
}: {
  proyecto: TareaProyecto;
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  plantillas: TareaPlantilla[];
  gestionarMiembros: boolean;
}) {
  const { miembrosPorProyecto } = useTareasContexto();
  const [detalleAbierto, setDetalleAbierto] = useState(false);

  const tareasDelProyecto = tareasDeProyecto(proyecto.id, hilos, tareas);
  const terminadas = contarTerminadas(tareasDelProyecto);
  const miembros = miembrosPorProyecto[proyecto.id]?.length ?? 0;

  return (
    <>
      <Isla
        titulo={proyecto.nombre}
        onAbrir={() => setDetalleAbierto(true)}
        badges={
          <>
            <span className={`badge shrink-0 ${proyecto.visibilidad === "privado" ? "badge-warning" : "badge-neutral"}`}>
              {proyecto.visibilidad === "privado" ? "Privado" : "Público"}
            </span>
            <span className="t-caption shrink-0 whitespace-nowrap">
              {terminadas}/{tareasDelProyecto.length} terminadas
            </span>
          </>
        }
        meta={
          <>
            {proyecto.descripcion && <span className="max-w-full truncate">{proyecto.descripcion}</span>}
            <span className="flex items-center gap-1">
              <Users size={13} strokeWidth={1.75} />
              {miembros} {miembros === 1 ? "miembro" : "miembros"}
            </span>
            <MetricasResumen createdAt={proyecto.created_at} tareas={tareasDelProyecto} />
          </>
        }
      />

      {detalleAbierto && (
        <ProyectoDetailPanel
          proyecto={proyecto}
          hilos={hilos}
          tareas={tareas}
          plantillas={plantillas}
          gestionarMiembros={gestionarMiembros}
          onClose={() => setDetalleAbierto(false)}
        />
      )}
    </>
  );
}
