"use client";

import { useRouter } from "next/navigation";
import { ListTodo } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { formatFecha, formatFechaHora } from "@/lib/utils";
import type { EventoAuditoria, TareaPendiente, Usuario } from "../types";

const ESTADO_LABEL: Record<string, string> = {
  pendiente: "Pendiente",
  en_progreso: "En progreso",
};

export function AuditoriaView({
  eventos,
  usuarios,
  pendientes,
  desde,
  hasta,
  usuarioId,
}: {
  eventos: EventoAuditoria[];
  usuarios: Usuario[];
  pendientes: TareaPendiente[];
  desde: string;
  hasta: string;
  usuarioId: string;
}) {
  const router = useRouter();
  const usuarioNombre = usuarios.find((u) => u.id === usuarioId)?.nombre;
  const { visibles, ...paginado } = usePaginado(eventos);

  function actualizarFiltro(next: { desde?: string; hasta?: string; usuario?: string }) {
    const params = new URLSearchParams({
      desde: next.desde ?? desde,
      hasta: next.hasta ?? hasta,
    });
    const usuario = next.usuario ?? usuarioId;
    if (usuario) params.set("usuario", usuario);
    router.push(`/tareas/auditoria?${params.toString()}`);
  }

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div>
          <label className="t-label mb-1 block">Desde</label>
          <input
            type="date"
            className="input"
            value={desde}
            onChange={(e) => actualizarFiltro({ desde: e.target.value })}
          />
        </div>
        <div>
          <label className="t-label mb-1 block">Hasta</label>
          <input
            type="date"
            className="input"
            value={hasta}
            onChange={(e) => actualizarFiltro({ hasta: e.target.value })}
          />
        </div>
        <div>
          <label className="t-label mb-1 block">Usuario</label>
          <select
            className="input"
            value={usuarioId}
            onChange={(e) => actualizarFiltro({ usuario: e.target.value })}
          >
            <option value="">Todos</option>
            {usuarios.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nombre}
              </option>
            ))}
          </select>
        </div>
      </div>

      {usuarioId && (
        <div className="mb-5 rounded-lg border border-border bg-bg-surface">
          <div className="flex items-center gap-2 border-b border-border p-3 px-5">
            <ListTodo size={15} strokeWidth={1.75} className="text-text-tertiary" />
            <p className="t-label">Pendiente de {usuarioNombre ?? "este usuario"} ({pendientes.length})</p>
          </div>
          {pendientes.length === 0 ? (
            <p className="t-caption p-3 px-5">Sin tareas pendientes — está al día.</p>
          ) : (
            pendientes.map((p) => (
              <div key={p.id} className="flex items-center gap-2 border-b border-border p-2.5 px-5 last:border-b-0">
                <div className="min-w-0 flex-1 truncate">
                  <span className="t-body-m">{p.titulo}</span>
                  {p.hilo_titulo && <span className="t-caption ml-2">· {p.hilo_titulo}</span>}
                </div>
                <div className="flex shrink-0 items-center gap-2 t-caption">
                  <span className="badge badge-neutral">{ESTADO_LABEL[p.estado] ?? p.estado}</span>
                  {p.fecha_vencimiento && <span>{formatFecha(p.fecha_vencimiento)}</span>}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      <Paginacion {...paginado} etiqueta="tareas completadas" />

      {eventos.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin resultados</p>
          <p className="t-body-m mt-1">Probá con otro rango de fechas o usuario.</p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((e) => (
            <div key={e.id} className="flex items-center gap-2 border-b border-border p-[13px] px-5 last:border-b-0">
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">{e.tareas?.titulo}</p>
                <p className="t-caption truncate">{e.usuarios?.nombre ?? "Sistema"}</p>
              </div>
              <p className="t-caption text-right">
                {[
                  e.tareas?.created_at && `Creada ${formatFecha(e.tareas.created_at)}`,
                  e.fecha_asignacion && `Asignada ${formatFecha(e.fecha_asignacion)}`,
                  `Completada ${formatFechaHora(e.created_at)}`,
                ]
                  .filter(Boolean)
                  .join(" → ")}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
