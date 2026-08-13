"use client";

import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { X } from "lucide-react";
import { Pagination } from "@/components/ui/Pagination";
import { formatFecha } from "@/lib/utils";
import { obtenerAuditoria } from "../actions";
import { TAREAS_PAGE_SIZE, type DiaAuditoria, type FiltrosAuditoria } from "../types";

function formatHora(iso: string): string {
  return new Date(iso).toLocaleTimeString("es-AR", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "America/Argentina/Buenos_Aires",
  });
}

export function AuditoriaView({
  diasIniciales,
  totalInicial,
  filtrosIniciales,
  usuarios,
  usuarioActualId,
}: {
  diasIniciales: DiaAuditoria[];
  totalInicial: number;
  filtrosIniciales: { desde: string; hasta: string };
  usuarios: { id: string; nombre: string }[];
  usuarioActualId: string;
}) {
  const [dias, setDias] = useState(diasIniciales);
  const [total, setTotal] = useState(totalInicial);
  const [page, setPage] = useState(0);
  const [cargando, setCargando] = useState(false);

  const [usuario, setUsuario] = useState("");
  const [desde, setDesde] = useState(filtrosIniciales.desde);
  const [hasta, setHasta] = useState(filtrosIniciales.hasta);

  const filtros: FiltrosAuditoria = {
    usuario_id: usuario || undefined,
    desde: desde || undefined,
    hasta: hasta || undefined,
  };
  const filtrosKey = `${usuario}|${desde}|${hasta}`;

  async function cargarPagina(p: number) {
    setCargando(true);
    try {
      const res = await obtenerAuditoria(filtros, p);
      setDias(res.dias);
      setTotal(res.total);
      setPage(p);
    } catch {
      toast.error("No se pudo cargar la auditoría");
    } finally {
      setCargando(false);
    }
  }

  const filtrosPrevios = useRef(filtrosKey);
  useEffect(() => {
    if (filtrosPrevios.current === filtrosKey) return;
    filtrosPrevios.current = filtrosKey;
    cargarPagina(0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtrosKey]);

  const rangoPorDefecto = desde === filtrosIniciales.desde && hasta === filtrosIniciales.hasta;

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-end gap-2">
        <div>
          <label className="t-label mb-1 block" htmlFor="auditoria-usuario">
            Usuario
          </label>
          <select
            id="auditoria-usuario"
            className="input !w-auto"
            value={usuario}
            onChange={(e) => setUsuario(e.target.value)}
          >
            <option value="">Todos los usuarios</option>
            {usuarios.map((u) => (
              <option key={u.id} value={u.id}>
                {u.id === usuarioActualId ? `${u.nombre} (vos)` : u.nombre}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="t-label mb-1 block" htmlFor="auditoria-desde">
            Desde
          </label>
          <input
            id="auditoria-desde"
            type="date"
            className="input !w-auto"
            value={desde}
            max={hasta}
            onChange={(e) => setDesde(e.target.value)}
          />
        </div>

        <div>
          <label className="t-label mb-1 block" htmlFor="auditoria-hasta">
            Hasta
          </label>
          <input
            id="auditoria-hasta"
            type="date"
            className="input !w-auto"
            value={hasta}
            min={desde}
            onChange={(e) => setHasta(e.target.value)}
          />
        </div>

        {(usuario || !rangoPorDefecto) && (
          <button
            className="btn btn-ghost btn-sm"
            onClick={() => {
              setUsuario("");
              setDesde(filtrosIniciales.desde);
              setHasta(filtrosIniciales.hasta);
            }}
          >
            <X size={14} />
            Limpiar
          </button>
        )}
      </div>

      <p className="t-caption mb-2">
        {cargando ? "Cargando..." : `${total} tarea${total === 1 ? "" : "s"} completada${total === 1 ? "" : "s"}`}
      </p>

      {dias.length === 0 ? (
        <div className="empty-state">Sin tareas completadas en este rango.</div>
      ) : (
        <div className="flex flex-col gap-4">
          {dias.map((dia) => (
            <div key={dia.dia} className="rounded-lg border border-border bg-bg-surface">
              <div className="flex items-center justify-between gap-3 border-b border-border px-5 py-3">
                <p className="t-body-m font-medium text-text-primary">{formatFecha(dia.dia)}</p>
                <span className="badge badge-neutral">{dia.eventos.length}</span>
              </div>

              <div className="flex flex-col">
                {dia.eventos.map((evento) => (
                  <div
                    key={evento.id}
                    className="flex items-center justify-between gap-3 border-b border-border p-[13px] px-5 last:border-b-0"
                  >
                    <div className="min-w-0">
                      <p className="t-body-m truncate font-medium text-text-primary">{evento.tarea_titulo}</p>
                      <p className="t-caption truncate">
                        {evento.usuario_nombre ?? "Sistema (recurrencia)"}
                        {evento.hilo_titulo && ` · ${evento.hilo_titulo}`}
                      </p>
                    </div>
                    <span className="t-caption shrink-0">{formatHora(evento.created_at)}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      <Pagination
        page={page}
        pageSize={TAREAS_PAGE_SIZE}
        total={total}
        cargando={cargando}
        onPageChange={cargarPagina}
      />
    </div>
  );
}
