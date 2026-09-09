"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  ArrowRightLeft,
  Bell,
  CalendarClock,
  CheckCircle2,
  ListTodo,
  XCircle,
  type LucideIcon,
} from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { formatFechaHora } from "@/lib/utils";
import { marcarLeida, marcarTodasLeidas } from "../actions";
import type { Avisos, Notificacion, TipoNotificacion } from "../types";

// El tipo llega como string desde el server component (nada no-serializable
// cruza el límite): el ícono y el texto se resuelven acá, mismo patrón que el
// ICON_MAP de SidebarNav.
const ICONO: Record<TipoNotificacion, LucideIcon> = {
  alta_aprobada: CheckCircle2,
  alta_rechazada: XCircle,
  obra_transferida: ArrowRightLeft,
  tarea_asignada: ListTodo,
};

const TEXTO: Record<TipoNotificacion, string> = {
  alta_aprobada: "Aprobaron el alta de",
  alta_rechazada: "Rechazaron el alta de",
  obra_transferida: "Te transfirieron",
  tarea_asignada: "Te asignaron",
};

// Los pares `-text` y no `text-success`/`text-error`: esos son hex fijos y en
// dark quedan en 3.8:1 (mismo defecto que cerró `.input-error-text`).
// `text-brand-500` sí es el color de ícono ya establecido en los dos temas.
const COLOR: Record<TipoNotificacion, string> = {
  alta_aprobada: "text-success-text",
  alta_rechazada: "text-error-text",
  obra_transferida: "text-brand-500",
  tarea_asignada: "text-brand-500",
};

// Las tareas no tienen ruta por id —la Lista abre el panel por estado, no por
// URL—, así que el aviso lleva a la vista.
const RUTA: Record<string, (id: string) => string> = {
  obra: (id) => `/obras/${id}`,
  empresa: (id) => `/obras/empresas/${id}`,
  persona: (id) => `/obras/personas/${id}`,
  tarea: () => "/tareas",
};

export function NotificacionesBell({
  notificaciones,
  avisos,
}: {
  notificaciones: Notificacion[];
  avisos: Avisos;
}) {
  const [abierto, setAbierto] = useState(false);
  const [pendiente, startTransition] = useTransition();
  const router = useRouter();

  const sinLeer = notificaciones.filter((n) => !n.leida).length;
  const totalAvisos = avisos.vencidas + avisos.vencen_hoy;

  function abrir(n: Notificacion) {
    setAbierto(false);
    startTransition(async () => {
      if (!n.leida) await marcarLeida(n.id);
      const ruta = RUTA[n.destino];
      if (ruta) router.push(ruta(n.destino_id));
    });
  }

  return (
    <>
      <button
        onClick={() => setAbierto(true)}
        className="icon-btn relative text-text-tertiary hover:text-text-secondary"
        aria-label={sinLeer > 0 ? `Notificaciones (${sinLeer} sin leer)` : "Notificaciones"}
      >
        <Bell size={18} strokeWidth={1.75} />
        {sinLeer > 0 && (
          <span className="absolute top-0.5 right-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-error px-1 text-[10px] font-semibold text-white">
            {sinLeer > 9 ? "9+" : sinLeer}
          </span>
        )}
      </button>

      {abierto && (
        <RightPanel
          title="Notificaciones"
          subtitle={sinLeer > 0 ? `${sinLeer} sin leer` : undefined}
          onClose={() => setAbierto(false)}
          footer={
            sinLeer > 0 ? (
              <button
                className="btn btn-secondary btn-sm"
                disabled={pendiente}
                onClick={() =>
                  startTransition(async () => {
                    await marcarTodasLeidas();
                  })
                }
              >
                Marcar todas como leídas
              </button>
            ) : undefined
          }
        >
          <div className="flex-1 overflow-y-auto">
            {totalAvisos > 0 && (
              <button
                onClick={() => {
                  setAbierto(false);
                  router.push("/tareas");
                }}
                className="flex w-full items-center gap-3 border-b border-border bg-warning-bg px-5 py-[13px] text-left"
              >
                <CalendarClock size={18} strokeWidth={1.75} className="shrink-0 text-warning-text" />
                <span className="t-body-m text-warning-text">
                  {avisos.vencidas > 0 && (
                    <>
                      {avisos.vencidas} {avisos.vencidas === 1 ? "tarea vencida" : "tareas vencidas"}
                    </>
                  )}
                  {avisos.vencidas > 0 && avisos.vencen_hoy > 0 && " · "}
                  {avisos.vencen_hoy > 0 && <>{avisos.vencen_hoy} vence{avisos.vencen_hoy === 1 ? "" : "n"} hoy</>}
                </span>
              </button>
            )}

            {notificaciones.length === 0 ? (
              <div className="p-8 text-center">
                <p className="t-body-m">No tenés notificaciones.</p>
                <p className="t-caption mt-1">
                  Acá vas a ver cuando te asignen una tarea, te transfieran una obra o resuelvan un alta tuya.
                </p>
              </div>
            ) : (
              <ul>
                {notificaciones.map((n) => {
                  const Icono = ICONO[n.tipo];
                  return (
                    <li key={n.id}>
                      <button
                        onClick={() => abrir(n)}
                        disabled={pendiente}
                        className={`tap-target flex w-full items-start gap-3 border-b border-border px-5 py-[13px] text-left hover:bg-bg-subtle ${
                          n.leida ? "" : "bg-brand-50/40"
                        }`}
                      >
                        <Icono
                          size={18}
                          strokeWidth={1.75}
                          className={`mt-0.5 shrink-0 ${COLOR[n.tipo]}`}
                        />
                        <span className="min-w-0 flex-1">
                          <span className="t-body-m block text-text-primary">
                            {TEXTO[n.tipo]}{" "}
                            <strong className="font-semibold">{n.etiqueta ?? "un registro"}</strong>
                          </span>
                          {n.motivo && (
                            <span className="t-body-m mt-0.5 block text-error-text">{n.motivo}</span>
                          )}
                          <span className="t-caption mt-1 block">
                            {[n.actor, formatFechaHora(n.created_at)].filter(Boolean).join(" · ")}
                          </span>
                        </span>
                        {!n.leida && (
                          <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-brand-500" aria-hidden />
                        )}
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </RightPanel>
      )}
    </>
  );
}
