"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import type { PresupuestoResumen } from "../queries";
import { AltaPresupuestoPanel } from "./AltaPresupuestoPanel";
import { FilaPresupuesto } from "./PresupuestosView";

// Sección "Presupuestos" en la ficha de la obra, compuesta en `app/` (GUIDE_ENTES §2.7). Sin `presupuestos_ver`, `app/`
// no la compone. *Nuevo presupuesto* abre el alta con la obra puesta, para quien arma en ella.
export function PresupuestosDeObra({
  obra,
  presupuestos,
  arma,
}: {
  obra: { id: string; nombre: string };
  presupuestos: Omit<PresupuestoResumen, "obra">[];
  arma: boolean;
}) {
  const [creando, setCreando] = useState(false);

  return (
    <div>
      <div className="mb-2 flex items-center">
        <p className="t-label flex-1">Presupuestos</p>
        {arma && (
          <button className="btn btn-secondary btn-sm" onClick={() => setCreando(true)}>
            <Plus size={14} />
            Nuevo presupuesto
          </button>
        )}
      </div>
      {presupuestos.length === 0 ? (
        <div className="empty-state empty-state-sm">
          <p className="t-body-m">
            {arma ? "Sin presupuestos todavía. Armá el primero con «Nuevo presupuesto»." : "Sin presupuestos todavía."}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {presupuestos.map((p) => (
            <FilaPresupuesto key={p.id} p={p} />
          ))}
        </div>
      )}
      {creando && <AltaPresupuestoPanel obras={[obra]} onClose={() => setCreando(false)} />}
    </div>
  );
}
