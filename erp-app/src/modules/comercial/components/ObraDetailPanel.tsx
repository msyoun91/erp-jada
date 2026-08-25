"use client";

import { RightPanel } from "@/components/ui/RightPanel";
import { formatFecha } from "@/lib/utils";
import type { Empresa, ObraConRelaciones, PersonaConEmpresa } from "../types";
import { Dato } from "./Dato";
import { ESTADO_OBRA_LABEL, TIPO_OBRA_LABEL } from "./comercialLabels";
import { ObraRelaciones } from "./ObraRelaciones";

export function ObraDetailPanel({
  obra,
  empresas,
  personas,
  gestionar,
  verComision,
  onClose,
}: {
  obra: ObraConRelaciones;
  empresas: Empresa[];
  personas: PersonaConEmpresa[];
  gestionar: boolean;
  verComision: boolean;
  onClose: () => void;
}) {
  return (
    <RightPanel
      title={obra.nombre}
      subtitle={[obra.direccion, obra.localidad].filter(Boolean).join(", ") || undefined}
      onClose={onClose}
    >
      <div className="flex flex-col gap-5 overflow-y-auto px-5 py-4">
        <section className="grid grid-cols-2 gap-3">
          <Dato label="Tipo" valor={TIPO_OBRA_LABEL[obra.tipo]} />
          <Dato label="Estado de obra" valor={ESTADO_OBRA_LABEL[obra.estado_obra]} />
          <Dato label="Provincia" valor={obra.provincia} />
          <Dato label="Unidades" valor={obra.cantidad_unidades} />
          <Dato
            label="Superficie"
            valor={obra.superficie_estimada ? `${obra.superficie_estimada} m²` : null}
          />
          <Dato
            label="Inicio estimado"
            valor={obra.fecha_estimada_inicio ? formatFecha(obra.fecha_estimada_inicio) : null}
          />
        </section>

        {obra.observaciones && (
          <section>
            <p className="t-label">Observaciones</p>
            <p className="t-body-m whitespace-pre-wrap text-text-primary">{obra.observaciones}</p>
          </section>
        )}

        <ObraRelaciones
          obra={obra}
          empresas={empresas}
          personas={personas}
          gestionar={gestionar}
          verComision={verComision}
        />
      </div>
    </RightPanel>
  );
}
