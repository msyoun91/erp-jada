"use client";

import { useTransition } from "react";
import { Archive, RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { setActivoObra } from "../actions";
import {
  BADGE_ESTADO,
  LABEL_ESTADO,
  LABEL_MOTIVO_PERDIDA,
  LABEL_ORIGEN,
  LABEL_PROVINCIA,
  LABEL_TIPO,
  type Obra,
  type Usuario,
} from "../types";
import { Breadcrumb } from "./Breadcrumb";
import { EstadoPendiente } from "./EstadoPendiente";
import { DatosGenerales } from "./ObraDatosGenerales";

// Desactivada es archivada para todos (sql/099): queda la identidad —nombre y
// datos generales, que quien la tenía compartida ya conocía— y no el contenido.
// Vínculos, compartir y tareas vuelven al reactivarla, tal como estaban.
export function ObraDesactivada({
  obra,
  responsable,
  esMio,
  puedeReactivar,
}: {
  obra: Obra;
  responsable: Usuario | null;
  esMio: boolean;
  puedeReactivar: boolean;
}) {
  const [pendiente, startTransition] = useTransition();

  function reactivar() {
    startTransition(async () => {
      const result = await setActivoObra(obra.id, true);
      if (result.success) toast.success("Obra reactivada");
      else toast.error(result.error);
    });
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
        <div className="flex min-w-0 items-center gap-2 sm:flex-1">
          <Breadcrumb padre="Obras" href="/obras" actual={obra.nombre} />
          <span className={`badge shrink-0 ${BADGE_ESTADO[obra.estado]}`}>
            {LABEL_ESTADO[obra.estado]}
          </span>
        </div>
        {puedeReactivar && (
          <button className="btn btn-secondary btn-sm" onClick={reactivar} disabled={pendiente}>
            <RotateCcw size={14} />
            Reactivar
          </button>
        )}
      </div>

      {/* Rechazar también desactiva, y esa no se reactiva (OB035): el aviso es
          el del rechazo, con su motivo. */}
      {obra.motivo_rechazo ? (
        <EstadoPendiente
          pendiente={false}
          motivoRechazo={obra.motivo_rechazo}
          queEs="Esta obra"
          detalle=""
        />
      ) : (
        <div className="flex gap-2 rounded-md border border-info/20 bg-info-bg px-3 py-2 text-info-text">
          <Archive size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
          <div className="min-w-0 flex-1">
            <p className="t-body-m font-semibold text-info-text">Esta obra está desactivada</p>
            <p className="t-caption mt-0.5 text-info-text">
              {esMio
                ? "No aparece en el listado y quien la tenía compartida dejó de verla. Al reactivarla vuelve todo como estaba."
                : "La desactivó su responsable. Si la reactiva, vuelve a aparecer."}
            </p>
          </div>
        </div>
      )}

      <DatosGenerales
        obra={obra}
        responsable={responsable}
        labels={{
          tipo: LABEL_TIPO,
          origen: LABEL_ORIGEN,
          provincia: LABEL_PROVINCIA,
          motivo: LABEL_MOTIVO_PERDIDA,
        }}
      />
    </div>
  );
}
