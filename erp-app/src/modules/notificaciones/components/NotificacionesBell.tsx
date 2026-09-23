"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Bell, KeyRound, ShieldCheck, UserPlus, type LucideIcon } from "lucide-react";
import { LABEL_MAP } from "@/components/layout/SidebarNav";
import { RightPanel } from "@/components/ui/RightPanel";
import { formatFechaHora } from "@/lib/utils";
import { marcarLeida, marcarTodasLeidas } from "../actions";
import type { Notificacion, TipoNotificacion } from "../types";

// El tipo llega como string desde el server component (nada no-serializable
// cruza el límite): el ícono y el texto se resuelven acá, mismo patrón que el
// ICON_MAP de SidebarNav. Cada evento nuevo suma su entrada en los tres mapas.
// Los colores van con los pares `-text` (`text-success-text`,
// `text-error-text`, `text-warning-text`) o `text-brand-500`: `text-success` y
// `text-error` son hex fijos y en dark quedan en 3.8:1.
const ICONO: Record<TipoNotificacion, LucideIcon> = {
  miembro_nuevo: UserPlus,
  permiso_otorgado: KeyRound,
  delegador_designado: ShieldCheck,
};
const TEXTO: Record<TipoNotificacion, string> = {
  miembro_nuevo: "Se sumó a tu equipo",
  permiso_otorgado: "Te dieron acceso a",
  delegador_designado: "Ahora sos el delegador de",
};
const COLOR: Record<TipoNotificacion, string> = {
  miembro_nuevo: "text-brand-500",
  permiso_otorgado: "text-success-text",
  delegador_designado: "text-success-text",
};

// `destino` → ruta. Cada rama de `notificaciones_listar` que devuelva un
// destino nuevo suma su entrada; sin entrada, el aviso no navega.
const RUTA: Record<string, (id: string) => string> = {
  mi_equipo: () => "/usuarios/mi-equipo",
  usuarios: () => "/usuarios",
};

// `permiso_otorgado` trae el módulo en `destino` y la vista en `etiqueta`: los
// nombres de vista no repiten el del módulo ("Ver"), así que solos no dicen nada.
function etiquetaDe(n: Notificacion): string | null {
  if (n.tipo === "permiso_otorgado" && n.destino && n.etiqueta) {
    return `${LABEL_MAP[n.destino] ?? n.destino} · ${n.etiqueta}`;
  }
  return n.etiqueta;
}

export function NotificacionesBell({ notificaciones }: { notificaciones: Notificacion[] }) {
  const [abierto, setAbierto] = useState(false);
  const [pendiente, startTransition] = useTransition();
  const router = useRouter();

  const sinLeer = notificaciones.filter((n) => !n.leida).length;

  function abrir(n: Notificacion) {
    setAbierto(false);
    startTransition(async () => {
      if (!n.leida) await marcarLeida(n.id);
      const ruta = n.destino ? RUTA[n.destino] : undefined;
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
            {notificaciones.length === 0 ? (
              <div className="p-8 text-center">
                <p className="t-body-m">No tenés notificaciones.</p>
              </div>
            ) : (
              <ul>
                {notificaciones.map((n) => {
                  const Icono: LucideIcon = ICONO[n.tipo];
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
                            <strong className="font-semibold">{etiquetaDe(n) ?? "un registro"}</strong>
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
