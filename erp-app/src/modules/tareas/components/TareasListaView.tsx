"use client";

import { useState } from "react";
import { Plus, Search } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { HiloCard } from "./HiloCard";
import { TareaRow } from "./TareaRow";
import { TareaFormPanel } from "./TareaFormPanel";
import { HiloFormPanel } from "./HiloFormPanel";
import { useOrdenTemperatura } from "../useOrdenTemperatura";

function esPropia(t: TareaConAsignados, usuarioActualId: string | null) {
  return (
    t.creado_por === usuarioActualId ||
    t.responsable_id === usuarioActualId ||
    t.tareas_asignados.some((a) => a.activo && a.usuario_id === usuarioActualId)
  );
}

export function TareasListaView({
  hilos,
  tareas,
  usuarios,
  proyectos,
  plantillas,
  gestionarAjenas,
  usuarioActualId,
}: {
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  plantillas: TareaPlantilla[];
  gestionarAjenas: boolean;
  usuarioActualId: string | null;
}) {
  const [texto, setTexto] = useState("");
  const [creandoTarea, setCreandoTarea] = useState(false);
  const [creandoHilo, setCreandoHilo] = useState(false);
  const { ordenar, onTemperaturaChange } = useOrdenTemperatura();

  function coincide(t: TareaConAsignados) {
    if (!esPropia(t, usuarioActualId)) return false;
    const q = texto.trim().toLowerCase();
    if (q && !t.titulo.toLowerCase().includes(q)) return false;
    return true;
  }

  const tareasSueltas = ordenar(tareas.filter((t) => t.hilo_id === null && coincide(t)));

  const hilosPropios = hilos.filter((h) => {
    const propioDirecto = h.creado_por === usuarioActualId || h.responsable_id === usuarioActualId;
    const tareasDelHilo = tareas.filter((t) => t.hilo_id === h.id);
    return propioDirecto || tareasDelHilo.some((t) => esPropia(t, usuarioActualId));
  });

  const hilosFiltrados = !texto
    ? hilosPropios
    : hilosPropios.filter((h) => {
        const hiloMatch = h.titulo.toLowerCase().includes(texto.trim().toLowerCase());
        const tareasDelHilo = tareas.filter((t) => t.hilo_id === h.id);
        return hiloMatch || tareasDelHilo.some(coincide);
      });

  const sinResultados = hilosFiltrados.length === 0 && tareasSueltas.length === 0;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="relative flex-1 min-w-[180px]">
          <Search
            size={14}
            strokeWidth={1.75}
            className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-text-tertiary"
          />
          <input
            type="text"
            value={texto}
            onChange={(e) => setTexto(e.target.value)}
            placeholder="Buscar tarea o hilo…"
            className="input py-1.5 pl-8"
          />
        </div>
        <button className="btn btn-secondary" onClick={() => setCreandoHilo(true)}>
          <Plus size={16} />
          Nuevo hilo
        </button>
        <button className="btn btn-primary" onClick={() => setCreandoTarea(true)}>
          <Plus size={16} />
          Nueva tarea
        </button>
      </div>

      {sinResultados ? (
        <div className="empty-state">
          <p className="t-h3">Sin tareas todavía</p>
          <p className="t-body-m mt-1">Creá la primera con &quot;Nueva tarea&quot; o &quot;Nuevo hilo&quot;.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-6">
          {hilosFiltrados.length > 0 && (
            <div className="flex flex-col gap-3">
              <p className="t-label text-text-tertiary">Hilos</p>
              {hilosFiltrados.map((h) => (
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

      {creandoTarea && (
        <TareaFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          usuarioActualId={usuarioActualId}
          onClose={() => setCreandoTarea(false)}
        />
      )}
      {creandoHilo && (
        <HiloFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          usuarioActualId={usuarioActualId}
          onClose={() => setCreandoHilo(false)}
        />
      )}
    </div>
  );
}
