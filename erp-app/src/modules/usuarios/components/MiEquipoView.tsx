"use client";

import { useState } from "react";
import { initials } from "@/lib/utils";
import type { MiEquipo, Miembro, Submodulo } from "../types";
import { DelegarPanel } from "./DelegarPanel";

export function MiEquipoView({
  miEquipo,
  submodulos,
  puedeDelegar,
}: {
  miEquipo: MiEquipo | null;
  submodulos: Submodulo[];
  puedeDelegar: boolean;
}) {
  const [abierto, setAbierto] = useState<Miembro | null>(null);

  if (!miEquipo) {
    return (
      <div className="empty-state">
        <p className="t-h3">No estás en un equipo</p>
        <p className="t-body-m mt-1">Los equipos los arma el administrador.</p>
      </div>
    );
  }

  const { yo, equipo, miembros, permisos } = miEquipo;
  const idDelegar = submodulos.find((s) => s.codigo === "usuarios_delegar")?.id;

  return (
    <div>
      <section className="rounded-lg border border-border bg-bg-surface">
        <header className="border-b border-border px-5 py-3">
          <h2 className="t-h3 truncate">{equipo.nombre}</h2>
          <p className="t-caption">
            {miembros.length} miembro{miembros.length !== 1 ? "s" : ""}
          </p>
        </header>

        {miembros.map((miembro) => {
          const cantidad = permisos[miembro.id]?.length ?? 0;
          const esYo = miembro.id === yo;

          return (
            <div
              key={miembro.id}
              className="flex items-center gap-3 border-b border-border row last:border-b-0"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand-50 text-[13px] font-semibold text-text-brand">
                {initials(miembro.nombre)}
              </div>
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">{miembro.nombre}</p>
                <p className="t-caption truncate">
                  {miembro.email}
                  {miembro.telefono && ` · ${miembro.telefono}`}
                </p>
              </div>
              {esYo && <span className="badge badge-neutral shrink-0">Vos</span>}
              {permisos[miembro.id]?.some((p) => p.submodulo_id === idDelegar) && (
                <span className="badge badge-info shrink-0">Delegador</span>
              )}
              {!miembro.activo && <span className="badge badge-neutral shrink-0">Inactivo</span>}
              {!esYo && (
                <button
                  type="button"
                  className="btn btn-secondary btn-sm shrink-0"
                  onClick={() => setAbierto(miembro)}
                >
                  {cantidad === 0 ? "Sin permisos" : `${cantidad} permiso${cantidad !== 1 ? "s" : ""}`}
                </button>
              )}
            </div>
          );
        })}
      </section>

      {abierto && (
        <DelegarPanel
          miembro={abierto}
          yo={yo}
          submodulos={submodulos}
          permisos={permisos}
          puedeDelegar={puedeDelegar}
          onClose={() => setAbierto(null)}
        />
      )}
    </div>
  );
}
