"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, ListChecks, Pencil, Plus, Users } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { ConfirmModal } from "@/components/ui/Modal";
import { desactivarProyecto } from "../actions";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto } from "../types";
import { HiloCard } from "./HiloCard";
import { TareaCard } from "./TareaCard";
import { TareaFormPanel } from "./TareaFormPanel";
import { HiloFormPanel } from "./HiloFormPanel";
import { ProyectoFormPanel } from "./ProyectoFormPanel";
import { MetricasResumen, contarTerminadas } from "./MetricasResumen";
import { puedeTrabajarEnProyecto, tareasDeProyecto } from "./proyectoTareas";
import { useOrdenTemperatura } from "../useOrdenTemperatura";
import { useTareasContexto } from "./tareasContexto";

// Panel del proyecto: agregar tarea/hilo directo al proyecto + listado de lo
// que ya tiene (mismas islas — HiloCard/TareaCard — que "Mis tareas", acá sin
// filtrar por "propio": el usuario confirmó que el panel muestra todo lo
// visible del proyecto, no solo lo suyo).
export function ProyectoDetailPanel({
  proyecto,
  hilos,
  tareas,
  plantillas,
  gestionarMiembros,
  onClose,
}: {
  proyecto: TareaProyecto;
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  plantillas: TareaPlantilla[];
  gestionarMiembros: boolean;
  onClose: () => void;
}) {
  const { miembrosPorProyecto, usuarioActualId, gestionarAjenas, puedeAsignar } = useTareasContexto();
  const [creandoTarea, setCreandoTarea] = useState(false);
  const [creandoHilo, setCreandoHilo] = useState(false);
  const [editando, setEditando] = useState(false);
  const [desactivando, setDesactivando] = useState(false);
  const { ordenar, onTemperaturaChange } = useOrdenTemperatura();
  // Hilo recién creado al convertir una tarea: se abre su panel solo.
  const [hiloConvertido, setHiloConvertido] = useState<string | null>(null);

  const hilosDelProyecto = hilos.filter((h) => h.proyecto_id === proyecto.id);
  const tareasDelProyecto = tareasDeProyecto(proyecto.id, hilos, tareas);
  const tareasSueltas = ordenar(tareasDelProyecto.filter((t) => t.hilo_id === null));
  const terminadas = contarTerminadas(tareasDelProyecto);
  const idsMiembros = miembrosPorProyecto[proyecto.id] ?? [];
  const miembros = idsMiembros.length;
  // Mismo USING que tareas_proyectos_update: manager, o creador que además
  // sigue siendo miembro (si se sacó a sí mismo ya no ve el proyecto).
  const puedeGestionar =
    gestionarAjenas ||
    (proyecto.creado_por === usuarioActualId && usuarioActualId !== null && idsMiembros.includes(usuarioActualId));
  // Ofrecer "Agregar hilo/tarea" sin poder trabajar acá abría un form que
  // siempre muere en la validación de asignados.
  const puedeTrabajar = puedeTrabajarEnProyecto(idsMiembros, usuarioActualId, puedeAsignar);

  // Archivar el proyecto se lleva sus hilos y sus tareas (trigger de sql/025) y
  // no hay reactivar en la UI: el modal dice cuánto se va antes de preguntar.
  // Cuenta lo visible, que es de lo que el usuario puede hacerse una idea.
  const arrastre = [
    hilosDelProyecto.length && `${hilosDelProyecto.length} ${hilosDelProyecto.length === 1 ? "hilo" : "hilos"}`,
    tareasDelProyecto.length &&
      `${tareasDelProyecto.length} ${tareasDelProyecto.length === 1 ? "tarea" : "tareas"}`,
  ]
    .filter(Boolean)
    .join(" y ");

  async function onDesactivar() {
    const result = await desactivarProyecto(proyecto.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Proyecto desactivado");
    onClose();
  }

  return (
    <RightPanel title={proyecto.nombre} onClose={onClose}>
      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto">
        <div className="flex flex-wrap items-center gap-2 border-b border-border row">
          {puedeTrabajar && (
            <>
              <button className="btn btn-ghost btn-sm" onClick={() => setCreandoHilo(true)}>
                <Plus size={14} strokeWidth={1.75} />
                Agregar hilo
              </button>
              <button className="btn btn-ghost btn-sm" onClick={() => setCreandoTarea(true)}>
                <Plus size={14} strokeWidth={1.75} />
                Agregar tarea
              </button>
            </>
          )}
          {puedeGestionar && (
            <>
              <button className="btn btn-ghost btn-sm" onClick={() => setEditando(true)}>
                <Pencil size={14} strokeWidth={1.75} />
                Modificar proyecto
              </button>
              <OverflowMenu
                items={[
                  {
                    label: "Desactivar",
                    icon: <Archive size={14} strokeWidth={1.75} />,
                    onClick: () => setDesactivando(true),
                    destructive: true,
                  },
                ]}
              />
            </>
          )}
        </div>

        <div className="flex flex-col gap-2 border-b border-border row">
          {proyecto.descripcion && <p className="t-body-m whitespace-pre-wrap">{proyecto.descripcion}</p>}
          <div className="t-caption flex flex-wrap items-center gap-3">
            <span className={`badge ${proyecto.visibilidad === "privado" ? "badge-warning" : "badge-neutral"}`}>
              {proyecto.visibilidad === "privado" ? "Privado" : "Público"}
            </span>
            <span className="flex items-center gap-1">
              <Users size={13} strokeWidth={1.75} />
              {miembros} {miembros === 1 ? "miembro" : "miembros"}
            </span>
            {tareasDelProyecto.length > 0 && (
              <span className="flex items-center gap-1">
                <ListChecks size={13} strokeWidth={1.75} />
                {terminadas}/{tareasDelProyecto.length} terminadas
              </span>
            )}
            <MetricasResumen createdAt={proyecto.created_at} tareas={tareasDelProyecto} />
          </div>
        </div>

        {hilosDelProyecto.length === 0 && tareasSueltas.length === 0 ? (
          <p className="t-caption px-5 py-3">
            Sin tareas ni hilos todavía
            {puedeTrabajar ? " — agregá el primero con los botones de arriba." : "."}
          </p>
        ) : (
          <div className="flex flex-col gap-4 row">
            {hilosDelProyecto.length > 0 && (
              <div className="flex flex-col gap-3">
                <p className="t-label text-text-tertiary">Hilos</p>
                {hilosDelProyecto.map((h) => (
                  <HiloCard
                    key={h.id}
                    hilo={h}
                    tareas={tareas}
                    plantillas={plantillas}
                    relacionCon={usuarioActualId}
                    autoAbrir={hiloConvertido === h.id}
                  />
                ))}
              </div>
            )}

            {tareasSueltas.length > 0 && (
              <div className="flex flex-col gap-3">
                <p className="t-label text-text-tertiary">Tareas sueltas</p>
                {tareasSueltas.map((t) => (
                  <TareaCard
                    key={t.id}
                    tarea={t}
                    hilosDisponibles={hilos}
                    relacionCon={usuarioActualId}
                    onTemperaturaChange={onTemperaturaChange}
                    onConvertida={setHiloConvertido}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {creandoTarea && (
        <TareaFormPanel
          proyectoId={proyecto.id}
          onClose={() => setCreandoTarea(false)}
        />
      )}
      {creandoHilo && (
        <HiloFormPanel
          proyectoId={proyecto.id}
          onClose={() => setCreandoHilo(false)}
        />
      )}
      {editando && (
        <ProyectoFormPanel
          proyecto={proyecto}
          miembrosActuales={idsMiembros}
          gestionarMiembros={gestionarMiembros}
          onClose={() => setEditando(false)}
        />
      )}
      {desactivando && (
        <ConfirmModal
          title="Desactivar proyecto"
          mensaje={`¿Desactivar el proyecto "${proyecto.nombre}"?${arrastre ? ` Se archivan con él ${arrastre}.` : ""}`}
          onConfirm={onDesactivar}
          onClose={() => setDesactivando(false)}
        />
      )}
    </RightPanel>
  );
}
