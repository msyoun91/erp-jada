"use client";

import { useMemo, useState } from "react";
import { Plus, History, ChevronDown, ChevronRight } from "lucide-react";
import { obtenerTareasCompletadas } from "../actions";
import type { TareaConRelaciones, TareaHilo } from "../types";
import { ESTADO_BADGE, ESTADO_LABEL } from "./estado";
import { CrearTareaPanel } from "./CrearTareaPanel";
import { CrearHiloPanel } from "./CrearHiloPanel";
import { HiloHistorialPanel } from "./HiloHistorialPanel";
import { TareaDetallePanel } from "./TareaDetallePanel";

function formatFecha(fecha: string | null) {
  if (!fecha) return null;
  return new Date(fecha + "T00:00:00").toLocaleDateString("es-AR");
}

type Grupo = { hiloId: string; hiloTitulo: string; tareas: TareaConRelaciones[] };

export function TareasView({
  tareasAbiertas,
  totalCompletadas,
  hilos,
  usuarios,
  usuarioActualId,
  puedeCrear,
  puedeAsignar,
  modo,
}: {
  tareasAbiertas: TareaConRelaciones[];
  totalCompletadas: number;
  hilos: TareaHilo[];
  usuarios: { id: string; nombre: string }[];
  usuarioActualId: string;
  puedeCrear: boolean;
  puedeAsignar: boolean;
  modo: "mis" | "todas";
}) {
  const [modalCrearTarea, setModalCrearTarea] = useState(false);
  const [modalCrearHilo, setModalCrearHilo] = useState(false);
  const [hiloAbierto, setHiloAbierto] = useState<string | null>(null);
  const [tareaAbierta, setTareaAbierta] = useState<TareaConRelaciones | null>(null);
  const [verCompletadas, setVerCompletadas] = useState(false);
  const [completadas, setCompletadas] = useState<TareaConRelaciones[] | null>(null);
  const [cargandoCompletadas, setCargandoCompletadas] = useState(false);

  async function onToggleCompletadas() {
    setVerCompletadas((v) => !v);
    if (completadas === null) {
      setCargandoCompletadas(true);
      setCompletadas(await obtenerTareasCompletadas(modo));
      setCargandoCompletadas(false);
    }
  }

  const { gruposAbiertos, sueltasAbiertas } = useMemo(() => {
    const porHilo = new Map<string, TareaConRelaciones[]>();
    const sueltas: TareaConRelaciones[] = [];

    for (const tarea of tareasAbiertas) {
      if (tarea.hilo_id) {
        const lista = porHilo.get(tarea.hilo_id) ?? [];
        lista.push(tarea);
        porHilo.set(tarea.hilo_id, lista);
      } else {
        sueltas.push(tarea);
      }
    }

    const grupos: Grupo[] = hilos
      .filter((h) => h.estado === "abierto")
      .map((h) => ({ hiloId: h.id, hiloTitulo: h.titulo, tareas: porHilo.get(h.id) ?? [] }));

    return { gruposAbiertos: grupos, sueltasAbiertas: sueltas };
  }, [tareasAbiertas, hilos]);

  const { gruposCerrados, sueltasCompletadas } = useMemo(() => {
    if (!completadas) return { gruposCerrados: [] as Grupo[], sueltasCompletadas: [] as TareaConRelaciones[] };

    const porHilo = new Map<string, TareaConRelaciones[]>();
    const sueltas: TareaConRelaciones[] = [];

    for (const tarea of completadas) {
      if (tarea.hilo_id) {
        const lista = porHilo.get(tarea.hilo_id) ?? [];
        lista.push(tarea);
        porHilo.set(tarea.hilo_id, lista);
      } else {
        sueltas.push(tarea);
      }
    }

    const grupos: Grupo[] = hilos
      .filter((h) => h.estado === "cerrado")
      .map((h) => ({ hiloId: h.id, hiloTitulo: h.titulo, tareas: porHilo.get(h.id) ?? [] }));

    return { gruposCerrados: grupos, sueltasCompletadas: sueltas };
  }, [completadas, hilos]);

  const vacio = gruposAbiertos.length === 0 && sueltasAbiertas.length === 0 && totalCompletadas === 0;

  return (
    <div>
      {puedeCrear && (
        <div className="mb-4 flex justify-end gap-2">
          <button className="btn btn-secondary" onClick={() => setModalCrearHilo(true)}>
            <Plus size={16} />
            Nuevo hilo
          </button>
          <button className="btn btn-primary" onClick={() => setModalCrearTarea(true)}>
            <Plus size={16} />
            Nueva tarea
          </button>
        </div>
      )}

      {vacio ? (
        <div className="empty-state">
          <p className="t-h3">Sin tareas todavía</p>
          {puedeCrear && <p className="t-body-m mt-1">Creá la primera con &quot;Nueva tarea&quot;.</p>}
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          {gruposAbiertos.length === 0 && sueltasAbiertas.length === 0 ? (
            <div className="empty-state">Sin tareas pendientes.</div>
          ) : (
            <>
              {gruposAbiertos.map((grupo) => (
                <GrupoHilo key={grupo.hiloId} grupo={grupo} onVerHistorial={() => setHiloAbierto(grupo.hiloId)} />
              ))}

              {sueltasAbiertas.length > 0 && (
                <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
                  {sueltasAbiertas.map((tarea) => (
                    <button key={tarea.id} onClick={() => setTareaAbierta(tarea)} className="text-left hover:bg-bg-subtle">
                      <TareaRow tarea={tarea} />
                    </button>
                  ))}
                </div>
              )}
            </>
          )}

          {totalCompletadas > 0 && (
            <div>
              <button
                className="t-caption flex items-center gap-1 text-text-brand"
                onClick={onToggleCompletadas}
              >
                {verCompletadas ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                Tareas completadas ({totalCompletadas})
              </button>

              {verCompletadas && (
                <div className="mt-2 flex flex-col gap-4">
                  {cargandoCompletadas ? (
                    <p className="t-caption">Cargando...</p>
                  ) : (
                    <>
                      {gruposCerrados.map((grupo) => (
                        <GrupoHilo key={grupo.hiloId} grupo={grupo} onVerHistorial={() => setHiloAbierto(grupo.hiloId)} />
                      ))}

                      {sueltasCompletadas.length > 0 && (
                        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
                          {sueltasCompletadas.map((tarea) => (
                            <button key={tarea.id} onClick={() => setTareaAbierta(tarea)} className="text-left hover:bg-bg-subtle">
                              <TareaRow tarea={tarea} />
                            </button>
                          ))}
                        </div>
                      )}
                    </>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {modalCrearTarea && (
        <CrearTareaPanel
          usuarioActualId={usuarioActualId}
          usuarios={usuarios}
          hilos={hilos}
          puedeAsignar={puedeAsignar}
          onClose={() => setModalCrearTarea(false)}
        />
      )}

      {modalCrearHilo && <CrearHiloPanel onClose={() => setModalCrearHilo(false)} />}

      {hiloAbierto && (
        <HiloHistorialPanel
          hiloId={hiloAbierto}
          usuarioActualId={usuarioActualId}
          usuarios={usuarios}
          puedeCrear={puedeCrear}
          puedeAsignar={puedeAsignar}
          onClose={() => setHiloAbierto(null)}
        />
      )}

      {tareaAbierta && (
        <TareaDetallePanel tarea={tareaAbierta} hilos={hilos} onClose={() => setTareaAbierta(null)} />
      )}
    </div>
  );
}

function GrupoHilo({ grupo, onVerHistorial }: { grupo: Grupo; onVerHistorial: () => void }) {
  return (
    <div className="rounded-lg border border-border bg-bg-surface">
      <button
        onClick={onVerHistorial}
        className="flex w-full items-center justify-between border-b border-border px-5 py-3 text-left hover:bg-bg-subtle"
      >
        <div className="flex items-center gap-2">
          <p className="t-body-m font-medium text-text-primary">{grupo.hiloTitulo}</p>
          <span className="badge badge-neutral">{grupo.tareas.length}</span>
        </div>
        <span className="t-caption flex items-center gap-1 text-text-brand">
          <History size={14} strokeWidth={1.75} />
          Ver historial
        </span>
      </button>
      {grupo.tareas.length > 0 && (
        <div className="flex flex-col">
          {grupo.tareas.map((tarea) => (
            <TareaRow key={tarea.id} tarea={tarea} />
          ))}
        </div>
      )}
    </div>
  );
}

function TareaRow({ tarea }: { tarea: TareaConRelaciones }) {
  const fecha = formatFecha(tarea.fecha_vencimiento);

  return (
    <div className="flex items-center justify-between border-b border-border p-[13px] px-5 last:border-b-0">
      <div>
        <p className="t-body-m font-medium text-text-primary">{tarea.titulo}</p>
        <p className="t-caption">
          {tarea.asignado_a_nombre}
          {fecha && ` · vence ${fecha}`}
        </p>
      </div>
      <span className={`badge ${ESTADO_BADGE[tarea.estado]}`}>{ESTADO_LABEL[tarea.estado]}</span>
    </div>
  );
}
