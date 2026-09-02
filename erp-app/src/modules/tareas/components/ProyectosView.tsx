"use client";

import { useState } from "react";
import { FolderPlus } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import type { TareaConAsignados, TareaHilo, TareaPlantilla } from "../types";
import { ProyectoFormPanel } from "./ProyectoFormPanel";
import { ProyectoCard } from "./ProyectoCard";
import { useTareasContexto } from "./tareasContexto";

export function ProyectosView({
  hilos,
  tareas,
  plantillas,
  gestionarMiembros,
  puedeCrear,
}: {
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  plantillas: TareaPlantilla[];
  gestionarMiembros: boolean;
  puedeCrear: boolean;
}) {
  const { usuarios, proyectos, miembrosPorProyecto, usuarioActualId, gestionarAjenas } = useTareasContexto();
  const [texto, setTexto] = useState("");
  // Mismo default que la vista Lista: arranca en uno mismo — "mis proyectos" —
  // y el panorama del equipo queda a un click. Filtra por membresía, que es
  // quién trabaja en el proyecto (`visibilidad` es otro eje: quién lo ve).
  const [miembroId, setMiembroId] = useState(usuarioActualId ?? "");
  const [creando, setCreando] = useState(false);

  const q = texto.trim().toLowerCase();
  const filtrados = proyectos.filter((p) => {
    if (q && !p.nombre.toLowerCase().includes(q) && !(p.descripcion ?? "").toLowerCase().includes(q)) return false;
    if (miembroId && !(miembrosPorProyecto[p.id] ?? []).includes(miembroId)) return false;
    return true;
  });
  const { visibles, ...paginado } = usePaginado(filtrados);

  // Mismo criterio que la vista Lista: sin tareas_gestionar_ajenas el filtro
  // ofrece solo "yo" y "Todos los usuarios".
  const opcionesUsuario = gestionarAjenas ? usuarios : usuarios.filter((u) => u.id === usuarioActualId);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar proyecto…" />
        <select
          data-tour="tareas_proyectos_miembro"
          className="input w-auto py-1.5"
          value={miembroId}
          onChange={(e) => setMiembroId(e.target.value)}
          aria-label="Filtrar por miembro"
        >
          <option value="">Todos los usuarios</option>
          {opcionesUsuario.map((u) => (
            <option key={u.id} value={u.id}>
              {u.nombre}
            </option>
          ))}
        </select>
        {puedeCrear && (
          <button
            data-tour="tareas_proyectos_crear"
            className="btn btn-primary"
            onClick={() => setCreando(true)}
          >
            <FolderPlus size={16} />
            Nuevo proyecto
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="proyectos" />

      {filtrados.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto || miembroId ? "Sin resultados" : "Sin proyectos todavía"}</p>
          <p className="t-body-m mt-1">
            {texto || miembroId
              ? "Probá con otro término de búsqueda o con otro usuario."
              : 'Creá el primero con "Nuevo proyecto".'}
          </p>
        </div>
      ) : (
        <div data-tour="tareas_proyectos_lista" className="flex flex-col gap-3">
          {visibles.map((p) => (
            <ProyectoCard
              key={p.id}
              proyecto={p}
              hilos={hilos}
              tareas={tareas}
              plantillas={plantillas}
              gestionarMiembros={gestionarMiembros}
            />
          ))}
        </div>
      )}

      {creando && (
        <ProyectoFormPanel
          gestionarMiembros={gestionarMiembros}
          onClose={() => setCreando(false)}
        />
      )}
    </div>
  );
}
