"use client";

import { EyeOff } from "lucide-react";
import { toast } from "sonner";
import { formatFechaHora } from "@/lib/utils";
import { ocultarEdicion } from "../actions";
import type { Edicion } from "../types";
import { useNombre, useTareas } from "./contexto";

const CAMPO: Record<string, string> = {
  titulo: "Título",
  descripcion: "Descripción",
  prioridad: "Prioridad",
  vence: "Vence",
  vence_dias: "Días de plazo",
  recurrencia_cantidad: "Recurrencia",
  recurrencia_unidad: "Unidad de recurrencia",
};

export function Historial({ ediciones }: { ediciones: Edicion[] }) {
  const { admin } = useTareas();
  const nombre = useNombre();
  if (ediciones.length === 0) return null;

  async function onOcultar(id: string) {
    const result = await ocultarEdicion(id);
    if (!result.success) toast.error(result.error);
    else toast.success("Entrada oculta");
  }

  return (
    <details>
      <summary className="t-label cursor-pointer py-2">Historial de cambios ({ediciones.length})</summary>
      <ul className="flex flex-col gap-2">
        {ediciones.map((e) => (
          <li key={e.id} className={`t-caption rounded-md p-2 ${e.activo ? "" : "bg-bg-subtle"}`}>
            <div className="flex items-center gap-2">
              <span className="font-semibold text-text-secondary">{CAMPO[e.campo] ?? e.campo}</span>
              <span>
                {nombre(e.actor_id)} · {formatFechaHora(e.created_at)}
              </span>
              {!e.activo && <span className="badge badge-neutral">Oculta</span>}
              <div className="flex-1" />
              {admin && e.activo && (
                <button className="icon-btn h-7 w-7" onClick={() => onOcultar(e.id)} aria-label="Ocultar entrada" title="Ocultar">
                  <EyeOff size={14} strokeWidth={1.75} />
                </button>
              )}
            </div>
            <p className="line-through">{e.anterior || "—"}</p>
            <p className="text-text-secondary">{e.nuevo || "—"}</p>
          </li>
        ))}
      </ul>
    </details>
  );
}
