"use client";

import { useRouter } from "next/navigation";
import { ListTodo } from "lucide-react";
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
              <div key={p.id} className="flex items-center justify-between border-b border-border p-2.5 px-5 last:border-b-0">
                <div>
                  <span className="t-body-m">{p.titulo}</span>
                  {p.hilo_titulo && <span className="t-caption ml-2">· {p.hilo_titulo}</span>}
                </div>
                <div className="flex items-center gap-2 t-caption">
                  <span className="badge badge-neutral">{ESTADO_LABEL[p.estado] ?? p.estado}</span>
                  {p.fecha_vencimiento && <span>{p.fecha_vencimiento}</span>}
                </div>
              </div>
            ))
          )}
        </div>
      )}

      <p className="t-caption mb-2">{eventos.length} tareas completadas</p>

      {eventos.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin resultados</p>
          <p className="t-body-m mt-1">Probá con otro rango de fechas o usuario.</p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {eventos.map((e) => (
            <div key={e.id} className="flex items-center justify-between border-b border-border p-[13px] px-5 last:border-b-0">
              <div>
                <p className="t-body-m font-medium text-text-primary">{e.tareas?.titulo}</p>
                <p className="t-caption">{e.usuarios?.nombre ?? "Sistema"}</p>
              </div>
              <div className="text-right t-caption">
                <p>Completada: {new Date(e.created_at).toLocaleString("es-AR")}</p>
                {e.tareas?.created_at && (
                  <p>Creada: {new Date(e.tareas.created_at).toLocaleDateString("es-AR")}</p>
                )}
                {e.fecha_asignacion && (
                  <p>Asignada: {new Date(e.fecha_asignacion).toLocaleDateString("es-AR")}</p>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
