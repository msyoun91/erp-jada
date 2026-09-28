"use client";

import { ENTES, type CodigoEnte } from "@/lib/entes";

// Los roles los declara el ente (`entes.roles`); los labels, `ENTES`.
export function RolesCheck({
  ente,
  valor,
  onCambio,
}: {
  ente: string;
  valor: string[];
  onCambio: (roles: string[]) => void;
}) {
  const roles: [string, string][] = Object.entries(ENTES[ente as CodigoEnte]?.roles ?? {});
  return (
    <fieldset>
      <legend className="t-label t-label-req mb-1">Rol</legend>
      <div className="flex flex-wrap gap-2">
        {roles.map(([codigo, label]) => {
          const elegido = valor.includes(codigo);
          return (
            <button
              key={codigo}
              type="button"
              aria-pressed={elegido}
              className={`btn btn-sm ${elegido ? "btn-primary" : "btn-secondary"}`}
              onClick={() => onCambio(elegido ? valor.filter((r) => r !== codigo) : [...valor, codigo])}
            >
              {label}
            </button>
          );
        })}
      </div>
    </fieldset>
  );
}
