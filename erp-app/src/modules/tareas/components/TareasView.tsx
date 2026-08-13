"use client";

import { useEffect, useMemo, useState } from "react";
import { Plus, History, ChevronDown, ChevronRight } from "lucide-react";
import { Pagination } from "@/components/ui/Pagination";
import { obtenerTareas } from "../actions";
import { TAREAS_PAGE_SIZE, type ModoTareas, type TareaConRelaciones, type TareaHilo } from "../types";
import { ESTADO_BADGE, ESTADO_LABEL, formatAntiguedad, formatPosponer, formatRecurrencia, formatVencimiento } from "./estado";
import { CrearTareaPanel } from "./CrearTareaPanel";
import { CrearHiloPanel } from "./CrearHiloPanel";
import { HiloHistorialPanel } from "./HiloHistorialPanel";
import { TareaDetallePanel } from "./TareaDetallePanel";

function hoyISO() {
  return new Date().toISOString().slice(0, 10);
}

type Grupo = {
  hiloId: string;
  hiloTitulo: string;
  hiloCreatedAt: string;
  recurrencia: string | null;
  pospuesto: string | null;
  tareas: TareaConRelaciones[];
};

function useBucketTareas(
  vista: "mis" | "todas",
  modo: ModoTareas,
  propTareas: TareaConRelaciones[] | null,
  propTotal: number
) {
  const [tareas, setTareas] = useState(propTareas ?? []);
  const [total, setTotal] = useState(propTotal);
  const [page, setPage] = useState(0);
  const [cargado, setCargado] = useState(propTareas !== null);
  const [cargando, setCargando] = useState(false);

  // propTareas viene del servidor (page 0) — cuando revalidatePath trae datos
  // frescos tras una mutación, resincroniza y vuelve a la primera página.
  useEffect(() => {
    if (propTareas === null) return;
    setTareas(propTareas);
    setTotal(propTotal);
    setPage(0);
    setCargado(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [propTareas, propTotal]);

  async function cargarPagina(p: number) {
    setCargando(true);
    const res = await obtenerTareas(vista, modo, p);
    setTareas(res.tareas);
    setTotal(res.total);
    setPage(p);
    setCargado(true);
    setCargando(false);
  }

  return { tareas, total, page, cargando, cargado, cargarPagina };
}

export function TareasView({
  tareasAbiertas,
  totalAbiertas,
  totalCompletadas,
  totalPospuestas,
  hilos,
  usuarios,
  usuarioActualId,
  puedeCrear,
  puedeAsignar,
  modo,
}: {
  tareasAbiertas: TareaConRelaciones[];
  totalAbiertas: number;
  totalCompletadas: number;
  totalPospuestas: number;
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
  const [verPospuestas, setVerPospuestas] = useState(false);

  const abiertas = useBucketTareas(modo, "abiertas", tareasAbiertas, totalAbiertas);
  const completadas = useBucketTareas(modo, "completadas", null, 0);
  const pospuestas = useBucketTareas(modo, "pospuestas", null, 0);

  async function onToggleCompletadas() {
    const abrir = !verCompletadas;
    setVerCompletadas(abrir);
    if (abrir && !completadas.cargado) await completadas.cargarPagina(0);
  }

  async function onTogglePospuestas() {
    const abrir = !verPospuestas;
    setVerPospuestas(abrir);
    if (abrir && !pospuestas.cargado) await pospuestas.cargarPagina(0);
  }

  const { gruposAbiertos, sueltasAbiertas } = useMemo(() => {
    const porHilo = new Map<string, TareaConRelaciones[]>();
    const sueltas: TareaConRelaciones[] = [];

    for (const tarea of abiertas.tareas) {
      if (tarea.hilo_id) {
        const lista = porHilo.get(tarea.hilo_id) ?? [];
        lista.push(tarea);
        porHilo.set(tarea.hilo_id, lista);
      } else {
        sueltas.push(tarea);
      }
    }

    const hoy = hoyISO();
    const grupos: Grupo[] = hilos
      .filter((h) => h.estado === "abierto" && !(h.posponer_hasta && h.posponer_hasta > hoy))
      .map((h) => ({
        hiloId: h.id,
        hiloTitulo: h.titulo,
        hiloCreatedAt: h.created_at,
        recurrencia: formatRecurrencia(h),
        pospuesto: null,
        tareas: porHilo.get(h.id) ?? [],
      }));

    return { gruposAbiertos: grupos, sueltasAbiertas: sueltas };
  }, [abiertas.tareas, hilos]);

  const { gruposCerrados, sueltasCompletadas } = useMemo(() => {
    if (!completadas.cargado) return { gruposCerrados: [] as Grupo[], sueltasCompletadas: [] as TareaConRelaciones[] };

    const porHilo = new Map<string, TareaConRelaciones[]>();
    const sueltas: TareaConRelaciones[] = [];

    for (const tarea of completadas.tareas) {
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
      .map((h) => ({
        hiloId: h.id,
        hiloTitulo: h.titulo,
        hiloCreatedAt: h.created_at,
        recurrencia: formatRecurrencia(h),
        pospuesto: null,
        tareas: porHilo.get(h.id) ?? [],
      }));

    return { gruposCerrados: grupos, sueltasCompletadas: sueltas };
  }, [completadas.cargado, completadas.tareas, hilos]);

  const hilosPospuestos = useMemo(() => {
    const hoy = hoyISO();
    const porHilo = new Map<string, TareaConRelaciones[]>();
    for (const tarea of abiertas.tareas) {
      if (tarea.hilo_id) {
        const lista = porHilo.get(tarea.hilo_id) ?? [];
        lista.push(tarea);
        porHilo.set(tarea.hilo_id, lista);
      }
    }

    return hilos
      .filter((h) => h.posponer_hasta && h.posponer_hasta > hoy)
      .map((h) => ({
        hiloId: h.id,
        hiloTitulo: h.titulo,
        hiloCreatedAt: h.created_at,
        recurrencia: formatRecurrencia(h),
        pospuesto: formatPosponer(h),
        tareas: porHilo.get(h.id) ?? [],
      }));
  }, [abiertas.tareas, hilos]);

  const vacio = totalAbiertas === 0 && totalCompletadas === 0 && totalPospuestas === 0;

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

          <Pagination
            page={abiertas.page}
            pageSize={TAREAS_PAGE_SIZE}
            total={abiertas.total}
            onPageChange={abiertas.cargarPagina}
          />

          {totalPospuestas > 0 && (
            <div>
              <button className="t-caption flex items-center gap-1 text-text-brand" onClick={onTogglePospuestas}>
                {verPospuestas ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                Pospuestas ({pospuestas.cargado ? pospuestas.total : totalPospuestas})
              </button>

              {verPospuestas && (
                <div className="mt-2 flex flex-col gap-4">
                  {pospuestas.cargando && !pospuestas.cargado ? (
                    <p className="t-caption">Cargando...</p>
                  ) : (
                    <>
                      {hilosPospuestos.map((grupo) => (
                        <GrupoHilo key={grupo.hiloId} grupo={grupo} onVerHistorial={() => setHiloAbierto(grupo.hiloId)} />
                      ))}

                      {pospuestas.tareas.length > 0 && (
                        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
                          {pospuestas.tareas.map((tarea) => (
                            <button key={tarea.id} onClick={() => setTareaAbierta(tarea)} className="text-left hover:bg-bg-subtle">
                              <TareaRow tarea={tarea} />
                            </button>
                          ))}
                        </div>
                      )}

                      <Pagination
                        page={pospuestas.page}
                        pageSize={TAREAS_PAGE_SIZE}
                        total={pospuestas.total}
                        onPageChange={pospuestas.cargarPagina}
                      />
                    </>
                  )}
                </div>
              )}
            </div>
          )}

          {totalCompletadas > 0 && (
            <div>
              <button className="t-caption flex items-center gap-1 text-text-brand" onClick={onToggleCompletadas}>
                {verCompletadas ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                Tareas completadas ({completadas.cargado ? completadas.total : totalCompletadas})
              </button>

              {verCompletadas && (
                <div className="mt-2 flex flex-col gap-4">
                  {completadas.cargando && !completadas.cargado ? (
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

                      <Pagination
                        page={completadas.page}
                        pageSize={TAREAS_PAGE_SIZE}
                        total={completadas.total}
                        onPageChange={completadas.cargarPagina}
                      />
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
  const antiguedad = formatAntiguedad({ created_at: grupo.hiloCreatedAt });

  return (
    <div className="rounded-lg border border-border bg-bg-surface">
      <button
        onClick={onVerHistorial}
        className="flex w-full items-center justify-between border-b border-border px-5 py-3 text-left hover:bg-bg-subtle"
      >
        <div>
          <div className="flex items-center gap-2">
            <p className="t-body-m font-medium text-text-primary">{grupo.hiloTitulo}</p>
            <span className="badge badge-neutral">{grupo.tareas.length}</span>
            <span className={`badge ${antiguedad.badge}`}>{antiguedad.texto}</span>
          </div>
          {grupo.recurrencia && <p className="t-caption">{grupo.recurrencia}</p>}
          {grupo.pospuesto && <p className="t-caption">{grupo.pospuesto}</p>}
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
  const vencimiento = formatVencimiento(tarea);
  const recurrencia = formatRecurrencia(tarea);
  const pospuesta = formatPosponer(tarea);

  return (
    <div className="flex items-center justify-between border-b border-border p-[13px] px-5 last:border-b-0">
      <div>
        <p className="t-body-m font-medium text-text-primary">{tarea.titulo}</p>
        <p className="t-caption">
          {tarea.asignado_a_nombre}
          {recurrencia && ` · ${recurrencia}`}
          {pospuesta && ` · ${pospuesta}`}
        </p>
      </div>
      <div className="flex items-center gap-2">
        {vencimiento && <span className={`badge ${vencimiento.badge}`}>{vencimiento.texto}</span>}
        <span className={`badge ${ESTADO_BADGE[tarea.estado]}`}>{ESTADO_LABEL[tarea.estado]}</span>
      </div>
    </div>
  );
}
