"use client";

import { useState } from "react";
import Link from "next/link";
import { Archive, Link2, Pencil, Plus } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { desactivarEmpresa } from "../actions";
import { copiarEnlace } from "../copiarEnlace";
import {
  LABEL_ESTADO,
  LABEL_PROVINCIA,
  LABEL_ROL_EMPRESA,
  type Empresa,
  type EstadoObra,
  type RolEmpresa,
} from "../types";
import { Dato, Observaciones } from "./Dato";
import { EmpresaFormPanel } from "./EmpresaFormPanel";
import { EstadoPendiente } from "./EstadoPendiente";
import { VincularObraPanel } from "./VincularObraPanel";
import { VincularPersonaEmpresaPanel } from "./VincularPersonaEmpresaPanel";

export function EmpresaDetalle({
  empresa,
  personas,
  obras,
  permisos,
}: {
  empresa: Empresa;
  personas: { id: string; persona_id: string; nombre: string; cargo: string | null; es_principal: boolean }[];
  obras: {
    id: string;
    obra_id: string;
    nombre: string;
    estado: EstadoObra;
    localidad: string | null;
    roles: RolEmpresa[];
    pendiente: boolean;
  }[];
  // Vincular personas y vincular obras son dos permisos distintos porque son
  // dos tablas distintas: `obras_personas_empresas` y `obras_vincular`.
  permisos: { editar: boolean; vincularPersona: boolean; vincularObra: boolean };
}) {
  const [editando, setEditando] = useState(false);
  const [desactivando, setDesactivando] = useState(false);
  const [vinculandoPersona, setVinculandoPersona] = useState(false);
  const [vinculandoObra, setVinculandoObra] = useState(false);

  const congelada = empresa.pendiente;

  return (
    <div className="flex flex-col gap-6">
      {/* Abajo de `sm` el título va en su propia línea: compartiendo la fila
          con las acciones se comía hasta quedar en una letra, y "Desactivar"
          quedaba arriba del nombre de lo que se está mirando. */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
        <div className="flex min-w-0 items-center gap-2 sm:flex-1">
          <Link href="/obras/empresas" className="btn btn-ghost btn-sm shrink-0">
            ← Empresas
          </Link>
          <h2 className="t-h2 min-w-0 flex-1 truncate">{empresa.razon_social}</h2>
        </div>
        <div className="flex items-center gap-2">
          {permisos.editar && (
            <button className="btn btn-secondary btn-sm" onClick={() => setEditando(true)}>
              <Pencil size={14} />
              Editar
            </button>
          )}
          <OverflowMenu
            items={[
              {
                label: "Copiar enlace",
                icon: <Link2 size={14} strokeWidth={1.75} />,
                onClick: () => copiarEnlace(`/obras/empresas/${empresa.id}`),
              },
              ...(permisos.editar
                ? [
                    {
                      label: "Desactivar empresa",
                      icon: <Archive size={14} strokeWidth={1.75} />,
                      onClick: () => setDesactivando(true),
                      destructive: true,
                    },
                  ]
                : []),
            ]}
          />
        </div>
      </div>

      <EstadoPendiente
        pendiente={empresa.pendiente}
        motivoRechazo={empresa.motivo_rechazo}
        queEs="Esta empresa"
        detalle="Se parece a una que ya existe. Solo la ves vos y no se puede vincular a obras ni a personas hasta que la autoricen."
      />

      <section className="card p-4">
        <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2 md:grid-cols-3">
          <Dato etiqueta="Nombre comercial" valor={empresa.nombre_comercial} />
          <Dato etiqueta="Teléfono" valor={empresa.telefono} />
          <Dato etiqueta="Email" valor={empresa.email} />
          <Dato etiqueta="Website" valor={empresa.website} />
          <Dato etiqueta="Dirección" valor={empresa.direccion} />
          <Dato
            etiqueta="Localidad"
            valor={
              empresa.localidad &&
              `${empresa.localidad}${empresa.provincia ? `, ${LABEL_PROVINCIA[empresa.provincia]}` : ""}`
            }
          />
        </dl>
        <Observaciones texto={empresa.observaciones} />
      </section>

      <section>
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Personas</h3>
          {/* El vínculo persona↔empresa se arma desde los dos lados: es la
              misma fila y el mismo permiso. */}
          {permisos.vincularPersona && !congelada && (
            <button className="btn btn-secondary btn-sm" onClick={() => setVinculandoPersona(true)}>
              <Plus size={14} />
              Vincular persona
            </button>
          )}
        </div>
        {personas.length === 0 ? (
          <div className="empty-state p-8">
            <p className="t-body-m">Ninguna persona vinculada a tu alcance.</p>
          </div>
        ) : (
          <ul className="flex flex-col gap-2">
            {personas.map((p) => (
              <li key={p.id} className="card p-3">
                <Link
                  href={`/obras/personas/${p.persona_id}`}
                  className="t-body-m block truncate font-semibold hover:underline"
                >
                  {p.nombre}
                </Link>
                <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
                  {p.cargo && <span className="t-caption">{p.cargo}</span>}
                  {p.es_principal && <span className="badge badge-neutral">Principal</span>}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Obras</h3>
          {permisos.vincularObra && !congelada && (
            <button className="btn btn-secondary btn-sm" onClick={() => setVinculandoObra(true)}>
              <Plus size={14} />
              Vincular obra
            </button>
          )}
        </div>
        {obras.length === 0 ? (
          // Las obras ajenas no se ven: la empresa es compartida, las obras no.
          <div className="empty-state p-8">
            <p className="t-body-m">Ninguna de tus obras tiene vinculada esta empresa.</p>
          </div>
        ) : (
          <ul className="flex flex-col gap-2">
            {obras.map((o) => (
              <li key={o.id} className="card p-3">
                <Link
                  href={`/obras/${o.obra_id}`}
                  className="t-body-m block truncate font-semibold hover:underline"
                >
                  {o.nombre}
                </Link>
                <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
                  <span className="t-caption">{LABEL_ESTADO[o.estado]}</span>
                  {o.localidad && <span className="t-caption">{o.localidad}</span>}
                  <span className="t-caption">
                    {o.roles.map((r) => LABEL_ROL_EMPRESA[r]).join(" · ")}
                  </span>
                  {o.pendiente && <span className="badge badge-warning">Pendiente</span>}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      {editando && <EmpresaFormPanel empresa={empresa} onClose={() => setEditando(false)} />}

      {vinculandoPersona && (
        <VincularPersonaEmpresaPanel
          empresa={{ id: empresa.id, razon_social: empresa.razon_social }}
          onClose={() => setVinculandoPersona(false)}
        />
      )}

      {vinculandoObra && (
        <VincularObraPanel
          empresa={{ id: empresa.id, razon_social: empresa.razon_social }}
          onClose={() => setVinculandoObra(false)}
        />
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar empresa"
          mensaje="Si participa en alguna obra activa —incluidas obras que no ves— la base lo va a impedir. Desvinculala primero."
          onConfirm={async () => {
            const result = await desactivarEmpresa(empresa.id);
            if (result.success) toast.success("Empresa desactivada");
            else toast.error(result.error);
          }}
          onClose={() => setDesactivando(false)}
        />
      )}
    </div>
  );
}
