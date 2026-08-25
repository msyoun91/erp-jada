"use client";

import { useState } from "react";
import { Building2, Pencil, Plus, UserMinus, UserPlus } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { quitarRelacionEmpresa, quitarRelacionPersona } from "../actions";
import type {
  Empresa,
  EmpresaConRoles,
  ObraConRelaciones,
  PersonaConEmpresa,
  PersonaConRoles,
} from "../types";
import {
  formatPorcentaje,
  nombreEmpresa,
  nombrePersona,
  ROL_EMPRESA_LABEL,
  ROL_PERSONA_LABEL,
} from "./comercialLabels";
import { RelacionEmpresaPanel } from "./RelacionEmpresaPanel";
import { RelacionPersonaPanel } from "./RelacionPersonaPanel";

// Las empresas y personas de una obra se leen igual desde la ficha de la obra
// y desde la del prospecto — es el mismo bloque, no dos que se parecen.
// `gestionar` decide si además se editan (función `comercial_obras_gestionar`).
export function ObraRelaciones({
  obra,
  empresas,
  personas,
  gestionar,
  verComision,
}: {
  obra: ObraConRelaciones;
  empresas: Empresa[];
  personas: PersonaConEmpresa[];
  gestionar: boolean;
  verComision: boolean;
}) {
  const [empresaPanel, setEmpresaPanel] = useState<EmpresaConRoles | "nueva" | null>(null);
  const [personaPanel, setPersonaPanel] = useState<PersonaConRoles | "nueva" | null>(null);
  const [quitandoEmpresa, setQuitandoEmpresa] = useState<EmpresaConRoles | null>(null);
  const [quitandoPersona, setQuitandoPersona] = useState<PersonaConRoles | null>(null);

  const empresasObra = obra.obra_empresa.filter((r) => r.activo);
  const personasObra = obra.obra_persona.filter((r) => r.activo);

  async function onQuitarEmpresa(relacion: EmpresaConRoles) {
    const result = await quitarRelacionEmpresa(relacion.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Empresa sacada de la obra");
  }

  async function onQuitarPersona(relacion: PersonaConRoles) {
    const result = await quitarRelacionPersona(relacion.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Persona sacada de la obra");
  }

  return (
    <>
      <section>
        <div className="mb-2 flex items-center justify-between gap-2">
          <h3 className="t-h3">Empresas</h3>
          {gestionar && (
            <button className="btn btn-secondary btn-sm" onClick={() => setEmpresaPanel("nueva")}>
              <Plus size={14} strokeWidth={1.75} />
              Agregar
            </button>
          )}
        </div>

        {empresasObra.length === 0 ? (
          <p className="t-caption">Sin empresas relacionadas.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {empresasObra.map((relacion) => (
              <li
                key={relacion.id}
                className="flex items-start gap-2 rounded-md border border-border p-2.5"
              >
                <Building2
                  size={16}
                  strokeWidth={1.75}
                  className="mt-0.5 shrink-0 text-text-tertiary"
                />
                <div className="min-w-0 flex-1">
                  <p className="t-body-m truncate font-medium text-text-primary">
                    {nombreEmpresa(relacion.empresas)}
                  </p>
                  <p className="t-caption">
                    {relacion.roles.map((rol) => ROL_EMPRESA_LABEL[rol]).join(" · ")}
                  </p>
                </div>
                {gestionar && (
                  <div className="flex shrink-0 gap-1">
                    <button
                      className="icon-btn text-text-tertiary"
                      aria-label="Modificar relación"
                      onClick={() => setEmpresaPanel(relacion)}
                    >
                      <Pencil size={14} strokeWidth={1.75} />
                    </button>
                    <button
                      className="icon-btn text-error"
                      aria-label="Sacar de la obra"
                      onClick={() => setQuitandoEmpresa(relacion)}
                    >
                      <UserMinus size={14} strokeWidth={1.75} />
                    </button>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <div className="mb-2 flex items-center justify-between gap-2">
          <h3 className="t-h3">Personas</h3>
          {gestionar && (
            <button className="btn btn-secondary btn-sm" onClick={() => setPersonaPanel("nueva")}>
              <UserPlus size={14} strokeWidth={1.75} />
              Agregar
            </button>
          )}
        </div>

        {personasObra.length === 0 ? (
          <p className="t-caption">Sin personas relacionadas.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {personasObra.map((relacion) => {
              const comision = relacion.comercial_comisiones.find((c) => c.activo);
              return (
                <li
                  key={relacion.id}
                  className="flex items-start gap-2 rounded-md border border-border p-2.5"
                >
                  <div className="min-w-0 flex-1">
                    <p className="t-body-m truncate font-medium text-text-primary">
                      {nombrePersona(relacion.personas)}
                      {relacion.es_referente && (
                        <span className="badge badge-brand ml-2">Referente</span>
                      )}
                    </p>
                    <p className="t-caption">
                      {[
                        relacion.empresas && nombreEmpresa(relacion.empresas),
                        relacion.roles.map((rol) => ROL_PERSONA_LABEL[rol]).join(" · "),
                      ]
                        .filter(Boolean)
                        .join(" — ")}
                    </p>
                    {verComision && comision && (
                      <p className="t-caption text-text-brand">
                        Comisión {formatPorcentaje(comision.porcentaje)}
                      </p>
                    )}
                  </div>
                  {gestionar && (
                    <div className="flex shrink-0 gap-1">
                      <button
                        className="icon-btn text-text-tertiary"
                        aria-label="Modificar relación"
                        onClick={() => setPersonaPanel(relacion)}
                      >
                        <Pencil size={14} strokeWidth={1.75} />
                      </button>
                      <button
                        className="icon-btn text-error"
                        aria-label="Sacar de la obra"
                        onClick={() => setQuitandoPersona(relacion)}
                      >
                        <UserMinus size={14} strokeWidth={1.75} />
                      </button>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {empresaPanel && (
        <RelacionEmpresaPanel
          obraId={obra.id}
          relacion={empresaPanel === "nueva" ? undefined : empresaPanel}
          empresas={empresas}
          yaRelacionadas={empresasObra.map((r) => r.empresa_id)}
          onClose={() => setEmpresaPanel(null)}
        />
      )}

      {personaPanel && (
        <RelacionPersonaPanel
          obraId={obra.id}
          relacion={personaPanel === "nueva" ? undefined : personaPanel}
          personas={personas}
          empresas={empresas}
          yaRelacionadas={personasObra.map((r) => r.persona_id)}
          hayOtroReferente={personasObra.some(
            (r) => r.es_referente && r.id !== (personaPanel === "nueva" ? null : personaPanel.id)
          )}
          verComision={verComision}
          onClose={() => setPersonaPanel(null)}
        />
      )}

      {quitandoEmpresa && (
        <ConfirmModal
          title="Sacar empresa de la obra"
          confirmLabel="Sacar"
          mensaje={`¿Sacar ${nombreEmpresa(quitandoEmpresa.empresas)} de esta obra? La empresa sigue existiendo.`}
          onConfirm={() => onQuitarEmpresa(quitandoEmpresa)}
          onClose={() => setQuitandoEmpresa(null)}
        />
      )}

      {quitandoPersona && (
        <ConfirmModal
          title="Sacar persona de la obra"
          confirmLabel="Sacar"
          mensaje={`¿Sacar a ${nombrePersona(quitandoPersona.personas)} de esta obra? Si tenía comisión configurada, se desactiva con la relación.`}
          onConfirm={() => onQuitarPersona(quitandoPersona)}
          onClose={() => setQuitandoPersona(null)}
        />
      )}
    </>
  );
}
