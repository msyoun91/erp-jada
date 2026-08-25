"use client";

import { RightPanel } from "@/components/ui/RightPanel";
import { formatFecha } from "@/lib/utils";
import type { Empresa, PersonaConEmpresa, ProspectoListado } from "../types";
import { Dato } from "./Dato";
import {
  ESTADO_OBRA_LABEL,
  ESTADO_PROSPECTO_BADGE,
  ESTADO_PROSPECTO_LABEL,
  formatMonto,
  nombrePersona,
  referente,
  TIPO_OBRA_LABEL,
} from "./comercialLabels";
import { ObraRelaciones } from "./ObraRelaciones";

export function ProspectoDetailPanel({
  prospecto,
  empresas,
  personas,
  gestionarObras,
  verComision,
  onClose,
}: {
  prospecto: ProspectoListado;
  empresas: Empresa[];
  personas: PersonaConEmpresa[];
  gestionarObras: boolean;
  verComision: boolean;
  onClose: () => void;
}) {
  const obra = prospecto.obras;
  const quienRefirio = obra ? referente(obra.obra_persona) : null;

  return (
    <RightPanel
      title={obra?.nombre ?? "Prospecto"}
      subtitle={[obra?.direccion, obra?.localidad].filter(Boolean).join(", ") || undefined}
      onClose={onClose}
    >
      <div className="flex flex-col gap-5 overflow-y-auto px-5 py-4">
        <div className="flex items-center gap-2">
          <span className={`badge ${ESTADO_PROSPECTO_BADGE[prospecto.estado_prospecto]}`}>
            {ESTADO_PROSPECTO_LABEL[prospecto.estado_prospecto]}
          </span>
          {obra && (
            <span className="badge badge-neutral">{ESTADO_OBRA_LABEL[obra.estado_obra]}</span>
          )}
        </div>

        <section>
          <h3 className="t-h3 mb-2">Información comercial</h3>
          <div className="grid grid-cols-2 gap-3">
            <Dato label="Responsable" valor={prospecto.usuarios?.nombre} />
            <Dato label="Fuente" valor={prospecto.comercial_fuentes?.nombre} />
            <Dato
              label="Potencial"
              valor={formatMonto(prospecto.potencial_estimado, prospecto.moneda_potencial)}
            />
            <Dato
              label="Compra estimada"
              valor={
                prospecto.fecha_estimada_compra
                  ? formatFecha(prospecto.fecha_estimada_compra)
                  : null
              }
            />
            <Dato
              label="Referente"
              valor={quienRefirio ? nombrePersona(quienRefirio.personas) : null}
            />
          </div>
          {prospecto.observaciones && (
            <p className="t-body-m mt-3 whitespace-pre-wrap text-text-primary">
              {prospecto.observaciones}
            </p>
          )}
        </section>

        {obra && (
          <>
            <section>
              <h3 className="t-h3 mb-2">Obra</h3>
              <div className="grid grid-cols-2 gap-3">
                <Dato label="Tipo" valor={TIPO_OBRA_LABEL[obra.tipo]} />
                <Dato label="Provincia" valor={obra.provincia} />
                <Dato label="Unidades" valor={obra.cantidad_unidades} />
                <Dato
                  label="Superficie"
                  valor={obra.superficie_estimada ? `${obra.superficie_estimada} m²` : null}
                />
                <Dato
                  label="Inicio estimado"
                  valor={
                    obra.fecha_estimada_inicio ? formatFecha(obra.fecha_estimada_inicio) : null
                  }
                />
              </div>
              {obra.observaciones && (
                <p className="t-body-m mt-3 whitespace-pre-wrap text-text-primary">
                  {obra.observaciones}
                </p>
              )}
            </section>

            <ObraRelaciones
              obra={obra}
              empresas={empresas}
              personas={personas}
              gestionar={gestionarObras}
              verComision={verComision}
            />
          </>
        )}
      </div>
    </RightPanel>
  );
}
