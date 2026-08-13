"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { Plus, History, ChevronDown, ChevronRight, Search, X } from "lucide-react";
import { Pagination } from "@/components/ui/Pagination";
import { hoyISO } from "@/lib/utils";
import { obtenerTareas } from "../actions";
import {
  TAREAS_PAGE_SIZE,
  type FiltrosTareas,
  type ModoTareas,
  type TareaConRelaciones,
  type TareaHilo,
} from "../types";
import { ESTADO_BADGE, ESTADO_LABEL, formatAntiguedad, formatPosponer, formatRecurrencia, formatVencimiento } from "./estado";
import { CrearTareaPanel } from "./CrearTareaPanel";
import { CrearHiloPanel } from "./CrearHiloPanel";
import { HiloHistorialPanel } from "./HiloHistorialPanel";
import { TareaDetallePanel } from "./TareaDetallePanel";

type Grupo = {
  hiloId: string;
  hiloTitulo: string;
  hiloCreatedAt: string;
  recurrencia: string | null;
  pospuesto: string | null;
  tareas: TareaConRelaciones[];
};

function estaPospuesto(h: TareaHilo, hoy: string) {
  return Boolean(h.posponer_hasta && h.posponer_hasta > hoy);
}

// Agrupa las tareas del bucket bajo sus hilos. `incluirHilo` decide qué hilos
// entran en la sección; un hilo puede entrar sin tareas (hilo recién creado) y
// toda tarea cuyo hilo quede afuera cae en `sueltas` en vez de desaparecer.
function agruparPorHilo(
  tareas: TareaConRelaciones[],
  hilos: TareaHilo[],
  incluirHilo: (hilo: TareaHilo, tieneTareas: boolean) => boolean
): { grupos: Grupo[]; sueltas: TareaConRelaciones[] } {
  const porHilo = new Map<string, TareaConRelaciones[]>();
  const sueltas: TareaConRelaciones[] = [];

  for (const tarea of tareas) {
    if (!tarea.hilo_id) {
      sueltas.push(tarea);
      continue;
    }
    const lista = porHilo.get(tarea.hilo_id) ?? [];
    lista.push(tarea);
    porHilo.set(tarea.hilo_id, lista);
  }

  const grupos = hilos
    .filter((h) => incluirHilo(h, (porHilo.get(h.id)?.length ?? 0) > 0))
    .map((h) => ({
      hiloId: h.id,
      hiloTitulo: h.titulo,
      hiloCreatedAt: h.created_at,
      recurrencia: formatRecurrencia(h),
      pospuesto: formatPosponer(h),
      tareas: porHilo.get(h.id) ?? [],
    }));

  const agrupadas = new Set(grupos.map((g) => g.hiloId));
  for (const [hiloId, lista] of porHilo) {
    if (!agrupadas.has(hiloId)) sueltas.push(...lista);
  }

  return { grupos, sueltas };
}

function useBucketTareas(
  vista: "mis" | "todas",
  modo: ModoTareas,
  datosServidor: { tareas: TareaConRelaciones[]; total: number } | null,
  syncKey: unknown,
  filtros: FiltrosTareas
) {
  const [tareas, setTareas] = useState(datosServidor?.tareas ?? []);
  const [total, setTotal] = useState(datosServidor?.total ?? 0);
  const [page, setPage] = useState(0);
  const [cargado, setCargado] = useState(datosServidor !== null);
  const [cargando, setCargando] = useState(false);

  const filtrosKey = `${filtros.texto ?? ""}|${filtros.asignado_a ?? ""}`;
  const hayFiltros = Boolean(filtros.texto || filtros.asignado_a);

  async function cargarPagina(p: number) {
    setCargando(true);
    try {
      const res = await obtenerTareas(vista, modo, p, filtros);
      setTareas(res.tareas);
      setTotal(res.total);
      setPage(p);
      setCargado(true);
    } catch {
      toast.error("No se pudieron cargar las tareas");
    } finally {
      setCargando(false);
    }
  }

  // syncKey cambia cuando revalidatePath trae datos frescos del servidor. El
  // bucket que recibe datos por props se resincroniza en render (patrón de
  // ajuste de estado por cambio de prop) y vuelve a la página 1.
  const [syncPrevio, setSyncPrevio] = useState(syncKey);
  if (syncKey !== syncPrevio) {
    setSyncPrevio(syncKey);
    if (datosServidor && !hayFiltros) {
      setTareas(datosServidor.tareas);
      setTotal(datosServidor.total);
      setPage(0);
      setCargado(true);
    }
  }

  // El bucket que no se resincronizó en render (el perezoso, o cualquiera con
  // filtros activos, porque las props del servidor vienen sin filtrar) vuelve a
  // pedir su página para no quedar viejo tras una mutación.
  useEffect(() => {
    if (!cargado || (datosServidor && !hayFiltros)) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- refetch a demanda tras revalidar, no dato inicial de página
    cargarPagina(page);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [syncKey]);

  // Cambio de filtros: vuelve a la página 1. El bucket todavía sin cargar no
  // pide nada — ya va a pedir con los filtros puestos cuando se lo expanda.
  const filtrosPrevios = useRef(filtrosKey);
  useEffect(() => {
    if (filtrosPrevios.current === filtrosKey) return;
    filtrosPrevios.current = filtrosKey;
    if (!cargado) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- refetch por filtro, no dato inicial de página
    cargarPagina(0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtrosKey]);

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

  const [texto, setTexto] = useState("");
  const [asignado, setAsignado] = useState("");
  const [filtros, setFiltros] = useState<FiltrosTareas>({});

  useEffect(() => {
    const id = setTimeout(
      () => setFiltros({ texto: texto.trim() || undefined, asignado_a: asignado || undefined }),
      300
    );
    return () => clearTimeout(id);
  }, [texto, asignado]);

  const hayFiltros = Boolean(filtros.texto || filtros.asignado_a);

  const abiertas = useBucketTareas(
    modo,
    "abiertas",
    { tareas: tareasAbiertas, total: totalAbiertas },
    tareasAbiertas,
    filtros
  );
  const completadas = useBucketTareas(modo, "completadas", null, tareasAbiertas, filtros);
  const pospuestas = useBucketTareas(modo, "pospuestas", null, tareasAbiertas, filtros);

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

  const hoy = hoyISO();

  // Con filtros activos un hilo solo entra si tiene tareas que pasaron el
  // filtro, o si su propio título coincide con la búsqueda — mostrar todos los
  // hilos vacíos ahogaría el resultado. Sin filtros, el hilo vacío se ve igual.
  const relevante = useMemo(() => {
    const q = filtros.texto?.toLowerCase() ?? "";
    return (h: TareaHilo, tieneTareas: boolean, incluirVacio: boolean) =>
      hayFiltros ? tieneTareas || (q !== "" && h.titulo.toLowerCase().includes(q)) : incluirVacio || tieneTareas;
  }, [filtros.texto, hayFiltros]);

  // Un hilo pospuesto se lleva sus tareas a la sección "Pospuestas", aunque las
  // tareas en sí no estén pospuestas — por eso salen del bucket de abiertas.
  const { grupos: gruposAbiertos, sueltas: sueltasAbiertas } = useMemo(
    () =>
      agruparPorHilo(
        abiertas.tareas,
        hilos,
        (h, tieneTareas) => !estaPospuesto(h, hoy) && relevante(h, tieneTareas, h.estado === "abierto")
      ),
    [abiertas.tareas, hilos, hoy, relevante]
  );

  const { grupos: gruposPospuestos } = useMemo(
    () =>
      agruparPorHilo(
        abiertas.tareas,
        hilos,
        (h, tieneTareas) => estaPospuesto(h, hoy) && relevante(h, tieneTareas, true)
      ),
    [abiertas.tareas, hilos, hoy, relevante]
  );

  const { grupos: gruposCerrados, sueltas: sueltasCompletadas } = useMemo(
    () =>
      completadas.cargado
        ? agruparPorHilo(completadas.tareas, hilos, (h, tieneTareas) =>
            relevante(h, tieneTareas, h.estado === "cerrado")
          )
        : { grupos: [] as Grupo[], sueltas: [] as TareaConRelaciones[] },
    [completadas.cargado, completadas.tareas, hilos, relevante]
  );

  // Los counts que manda el servidor no conocen los filtros: con filtros
  // activos, la sección colapsada no muestra número hasta que se la abre.
  const contar = (bucket: { cargado: boolean; total: number }, totalServidor: number, extra = 0) =>
    hayFiltros && !bucket.cargado ? null : bucket.cargado ? bucket.total + extra : totalServidor + extra;

  const hayPospuestas = totalPospuestas > 0 || gruposPospuestos.length > 0;
  const countPospuestas = contar(pospuestas, totalPospuestas, gruposPospuestos.length);
  const countCompletadas = contar(completadas, totalCompletadas);
  const vacio =
    totalAbiertas === 0 && totalCompletadas === 0 && totalPospuestas === 0 && hilos.length === 0;

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

      {!vacio && (
        <div className="mb-4 flex flex-wrap items-center gap-2">
          <div className="relative min-w-[200px] flex-1">
            <Search
              size={15}
              strokeWidth={1.75}
              className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-tertiary"
            />
            <input
              className="input pl-9"
              placeholder="Buscar por título o descripción..."
              aria-label="Buscar tareas"
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
            />
          </div>

          {modo === "todas" && (
            <select
              className="input !w-auto"
              aria-label="Filtrar por asignado"
              value={asignado}
              onChange={(e) => setAsignado(e.target.value)}
            >
              <option value="">Todos los asignados</option>
              {usuarios.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.id === usuarioActualId ? `${u.nombre} (vos)` : u.nombre}
                </option>
              ))}
            </select>
          )}

          {(texto || asignado) && (
            <button
              className="btn btn-ghost btn-sm"
              onClick={() => {
                setTexto("");
                setAsignado("");
              }}
            >
              <X size={14} />
              Limpiar
            </button>
          )}
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
            <div className="empty-state">
              {hayFiltros ? "Sin resultados para el filtro." : "Sin tareas pendientes."}
            </div>
          ) : (
            <>
              {gruposAbiertos.map((grupo) => (
                <GrupoHilo key={grupo.hiloId} grupo={grupo} onVerHistorial={() => setHiloAbierto(grupo.hiloId)} />
              ))}

              {sueltasAbiertas.length > 0 && (
                <ListaTareas tareas={sueltasAbiertas} onAbrir={setTareaAbierta} />
              )}
            </>
          )}

          <Pagination
            page={abiertas.page}
            pageSize={TAREAS_PAGE_SIZE}
            total={abiertas.total}
            cargando={abiertas.cargando}
            onPageChange={abiertas.cargarPagina}
          />

          {hayPospuestas && (
            <div>
              <button className="t-caption flex items-center gap-1 text-text-brand" onClick={onTogglePospuestas}>
                {verPospuestas ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                Pospuestas{countPospuestas === null ? "" : ` (${countPospuestas})`}
              </button>

              {verPospuestas && (
                <div className="mt-2 flex flex-col gap-4">
                  {gruposPospuestos.map((grupo) => (
                    <GrupoHilo key={grupo.hiloId} grupo={grupo} onVerHistorial={() => setHiloAbierto(grupo.hiloId)} />
                  ))}

                  {pospuestas.cargando && !pospuestas.cargado ? (
                    <p className="t-caption">Cargando...</p>
                  ) : (
                    <>
                      {pospuestas.tareas.length > 0 && (
                        <ListaTareas tareas={pospuestas.tareas} onAbrir={setTareaAbierta} />
                      )}

                      {gruposPospuestos.length === 0 && pospuestas.tareas.length === 0 && (
                        <div className="empty-state">Sin resultados para el filtro.</div>
                      )}

                      <Pagination
                        page={pospuestas.page}
                        pageSize={TAREAS_PAGE_SIZE}
                        total={pospuestas.total}
                        cargando={pospuestas.cargando}
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
                Tareas completadas{countCompletadas === null ? "" : ` (${countCompletadas})`}
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
                        <ListaTareas tareas={sueltasCompletadas} onAbrir={setTareaAbierta} />
                      )}

                      {gruposCerrados.length === 0 && sueltasCompletadas.length === 0 && (
                        <div className="empty-state">Sin resultados para el filtro.</div>
                      )}

                      <Pagination
                        page={completadas.page}
                        pageSize={TAREAS_PAGE_SIZE}
                        total={completadas.total}
                        cargando={completadas.cargando}
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

function ListaTareas({
  tareas,
  onAbrir,
}: {
  tareas: TareaConRelaciones[];
  onAbrir: (tarea: TareaConRelaciones) => void;
}) {
  return (
    <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
      {tareas.map((tarea) => (
        <button key={tarea.id} onClick={() => onAbrir(tarea)} className="block text-left hover:bg-bg-subtle">
          <TareaRow tarea={tarea} />
        </button>
      ))}
    </div>
  );
}

function GrupoHilo({ grupo, onVerHistorial }: { grupo: Grupo; onVerHistorial: () => void }) {
  const antiguedad = formatAntiguedad({ created_at: grupo.hiloCreatedAt });

  return (
    <div className="rounded-lg border border-border bg-bg-surface">
      <button
        onClick={onVerHistorial}
        className="flex w-full items-center justify-between gap-3 border-b border-border px-5 py-3 text-left hover:bg-bg-subtle"
      >
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <p className="t-body-m truncate font-medium text-text-primary">{grupo.hiloTitulo}</p>
            <span className="badge badge-neutral">{grupo.tareas.length}</span>
            <span className={`badge ${antiguedad.badge}`}>{antiguedad.texto}</span>
          </div>
          {grupo.recurrencia && <p className="t-caption truncate">{grupo.recurrencia}</p>}
          {grupo.pospuesto && <p className="t-caption truncate">{grupo.pospuesto}</p>}
        </div>
        <span className="t-caption flex shrink-0 items-center gap-1 text-text-brand">
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
    <div className="flex w-full items-center justify-between gap-3 border-b border-border p-[13px] px-5 last:border-b-0">
      <div className="min-w-0">
        <p className="t-body-m truncate font-medium text-text-primary">{tarea.titulo}</p>
        <p className="t-caption truncate">
          {tarea.asignado_a_nombre}
          {tarea.hilo_titulo && ` · ${tarea.hilo_titulo}`}
          {recurrencia && ` · ${recurrencia}`}
          {pospuesta && ` · ${pospuesta}`}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {vencimiento && <span className={`badge ${vencimiento.badge}`}>{vencimiento.texto}</span>}
        <span className={`badge ${ESTADO_BADGE[tarea.estado]}`}>{ESTADO_LABEL[tarea.estado]}</span>
      </div>
    </div>
  );
}
