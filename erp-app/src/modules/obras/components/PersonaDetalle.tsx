"use client";

import { useState } from "react";
import Link from "next/link";
import { Pencil, Plus } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { desactivarPersona, desvincularPersonaEmpresa } from "../actions";
import { LABEL_ESTADO, LABEL_ROL_PERSONA, type EstadoObra, type RolPersona } from "../types";
import { PersonaFormPanel, type PersonaEditable } from "./PersonaFormPanel";
import { VincularPersonaEmpresaPanel } from "./VincularPersonaEmpresaPanel";

export function PersonaDetalle({
  persona,
  empresas,
  obras,
  empresasDisponibles,
  permisos,
}: {
  persona: PersonaEditable;
  empresas: { id: string; empresa_id: string; razon_social: string; cargo: string | null; es_principal: boolean }[];
  obras: {
    id: string;
    obra_id: string;
    nombre: string;
    estado: EstadoObra;
    empresa: string | null;
    roles: RolPersona[];
    comision: number | null;
  }[];
  empresasDisponibles: { id: string; razon_social: string }[];
  permisos: { editar: boolean; vincularEmpresa: boolean };
}) {
  const [editando, setEditando] = useState(false);
  const [vinculando, setVinculando] = useState(false);
  const [desactivando, setDesactivando] = useState(false);

  const nombre = `${persona.nombre} ${persona.apellido ?? ""}`.trim();

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-2">
        <Link href="/obras/personas" className="btn btn-ghost btn-sm">
          ← Personas
        </Link>
        <h2 className="t-h2 min-w-0 flex-1 truncate">{nombre}</h2>
        {permisos.editar && (
          <>
            <button className="btn btn-secondary btn-sm" onClick={() => setEditando(true)}>
              <Pencil size={14} />
              Editar
            </button>
            <button className="btn btn-danger btn-sm" onClick={() => setDesactivando(true)}>
              Desactivar
            </button>
          </>
        )}
      </div>

      <section className="card p-4">
        <dl className="grid grid-cols-2 gap-4 md:grid-cols-3">
          {persona.telefono && (
            <div>
              <dt className="t-caption">Teléfono</dt>
              <dd className="t-body-m">
                <a href={`tel:${persona.telefono}`} className="hover:underline">
                  {persona.telefono}
                </a>
              </dd>
            </div>
          )}
          {persona.whatsapp && (
            <div>
              <dt className="t-caption">WhatsApp</dt>
              <dd className="t-body-m">{persona.whatsapp}</dd>
            </div>
          )}
          {persona.email && (
            <div>
              <dt className="t-caption">Email</dt>
              <dd className="t-body-m">
                <a href={`mailto:${persona.email}`} className="hover:underline">
                  {persona.email}
                </a>
              </dd>
            </div>
          )}
        </dl>
        {persona.observaciones && (
          <p className="t-body-m mt-4 whitespace-pre-wrap">{persona.observaciones}</p>
        )}
      </section>

      <section>
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Empresas</h3>
          {permisos.vincularEmpresa && (
            <button className="btn btn-secondary btn-sm" onClick={() => setVinculando(true)}>
              <Plus size={14} />
              Vincular
            </button>
          )}
        </div>
        {empresas.length === 0 ? (
          <p className="t-caption">Sin empresa conocida.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {empresas.map((e) => (
              <li key={e.id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                <Link
                  href={`/obras/empresas/${e.empresa_id}`}
                  className="t-body-m min-w-0 flex-1 truncate font-semibold hover:underline"
                >
                  {e.razon_social}
                </Link>
                {e.cargo && <span className="t-caption">{e.cargo}</span>}
                {e.es_principal && <span className="badge badge-neutral">Principal</span>}
                {permisos.vincularEmpresa && (
                  <button
                    className="btn btn-ghost btn-sm"
                    onClick={async () => {
                      const result = await desvincularPersonaEmpresa(e.id, persona.id);
                      if (result.success) toast.success("Vínculo quitado");
                      else toast.error(result.error);
                    }}
                  >
                    Quitar
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <h3 className="t-h3 mb-2">Obras</h3>
        {obras.length === 0 ? (
          <p className="t-caption">No participa en ninguna de tus obras.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {obras.map((o) => (
              <li key={o.id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                <Link
                  href={`/obras/${o.obra_id}`}
                  className="t-body-m min-w-0 flex-1 truncate font-semibold hover:underline"
                >
                  {o.nombre}
                </Link>
                <span className="t-caption">{LABEL_ESTADO[o.estado]}</span>
                {o.empresa && <span className="t-caption">{o.empresa}</span>}
                <span className="t-caption">
                  {o.roles.map((r) => LABEL_ROL_PERSONA[r]).join(" · ")}
                </span>
                {o.comision !== null && (
                  <span className="badge badge-brand">Referente {o.comision.toFixed(2)}%</span>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      {editando && <PersonaFormPanel persona={persona} onClose={() => setEditando(false)} />}

      {vinculando && (
        <VincularPersonaEmpresaPanel
          personaId={persona.id}
          empresas={empresasDisponibles}
          onClose={() => setVinculando(false)}
        />
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar persona"
          mensaje="Si participa en alguna obra activa —incluidas obras que no ves— la base lo va a impedir. Desvinculala primero."
          onConfirm={async () => {
            const result = await desactivarPersona(persona.id);
            if (result.success) toast.success("Persona desactivada");
            else toast.error(result.error);
          }}
          onClose={() => setDesactivando(false)}
        />
      )}
    </div>
  );
}
