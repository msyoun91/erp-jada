"use client";

import { useState } from "react";
import Link from "next/link";
import { Archive, Link2, Pencil, Plus, Unlink } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { desactivarPersona, desvincularPersonaEmpresa } from "../actions";
import { copiarEnlace } from "../copiarEnlace";
import { LABEL_ESTADO, LABEL_ROL_PERSONA, type EstadoObra, type RolPersona } from "../types";
import { EstadoPendiente } from "./EstadoPendiente";
import { PersonaFormPanel, type PersonaEditable } from "./PersonaFormPanel";
import { VincularObraPanel } from "./VincularObraPanel";
import { VincularPersonaEmpresaPanel } from "./VincularPersonaEmpresaPanel";

export function PersonaDetalle({
  persona,
  estado,
  empresas,
  obras,
  permisos,
}: {
  persona: PersonaEditable;
  // `obras_ficha_persona` sirve los datos de contacto y nada más: el estado de
  // autorización viaja aparte para no tener que cambiarle la firma.
  estado: { pendiente: boolean; motivo_rechazo: string | null };
  empresas: { id: string; empresa_id: string; razon_social: string; cargo: string | null; es_principal: boolean }[];
  obras: {
    id: string;
    obra_id: string;
    nombre: string;
    estado: EstadoObra;
    empresa: string | null;
    roles: RolPersona[];
    comision: number | null;
    pendiente: boolean;
  }[];
  permisos: { editar: boolean; vincularEmpresa: boolean; vincularObra: boolean };
}) {
  const [editando, setEditando] = useState(false);
  const [vinculando, setVinculando] = useState(false);
  const [vinculandoObra, setVinculandoObra] = useState(false);
  const [desactivando, setDesactivando] = useState(false);

  const nombre = `${persona.nombre} ${persona.apellido ?? ""}`.trim();

  return (
    <div className="flex flex-col gap-6">
      {/* Abajo de `sm` el título va en su propia línea: compartiendo la fila
          con las acciones se comía hasta quedar en una letra, y "Desactivar"
          quedaba arriba del nombre de lo que se está mirando. */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
        <div className="flex min-w-0 items-center gap-2 sm:flex-1">
          <Link href="/obras/personas" className="btn btn-ghost btn-sm shrink-0">
            ← Personas
          </Link>
          <h2 className="t-h2 min-w-0 flex-1 truncate">{nombre}</h2>
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
                onClick: () => copiarEnlace(`/obras/personas/${persona.id}`),
              },
              ...(permisos.editar
                ? [
                    {
                      label: "Desactivar persona",
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
        pendiente={estado.pendiente}
        motivoRechazo={estado.motivo_rechazo}
        queEs="Esta persona"
        detalle="Se parece a una que ya existe. Solo la ves vos y no se puede vincular a obras ni a empresas hasta que la autoricen."
      />

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
          {permisos.vincularEmpresa && !estado.pendiente && (
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
              <li key={e.id} className="card flex items-center gap-3 p-3">
                <div className="min-w-0 flex-1">
                  <Link
                    href={`/obras/empresas/${e.empresa_id}`}
                    className="t-body-m block truncate font-semibold hover:underline"
                  >
                    {e.razon_social}
                  </Link>
                  <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
                    {e.cargo && <span className="t-caption">{e.cargo}</span>}
                    {e.es_principal && <span className="badge badge-neutral">Principal</span>}
                  </div>
                </div>
                {permisos.vincularEmpresa && (
                  <OverflowMenu
                    items={[
                      {
                        label: "Quitar de la empresa",
                        icon: <Unlink size={14} strokeWidth={1.75} />,
                        onClick: async () => {
                          const result = await desvincularPersonaEmpresa(e.id, persona.id);
                          if (result.success) toast.success("Vínculo quitado");
                          else toast.error(result.error);
                        },
                        destructive: true,
                      },
                    ]}
                  />
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Obras</h3>
          {/* El vínculo obra↔persona también se arma desde acá: parado en la
              agenda, la obra es lo que se busca. */}
          {permisos.vincularObra && !estado.pendiente && (
            <button className="btn btn-secondary btn-sm" onClick={() => setVinculandoObra(true)}>
              <Plus size={14} />
              Vincular obra
            </button>
          )}
        </div>
        {obras.length === 0 ? (
          <p className="t-caption">No participa en ninguna de tus obras.</p>
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
                  {o.empresa && <span className="t-caption">{o.empresa}</span>}
                  <span className="t-caption">
                    {o.roles.map((r) => LABEL_ROL_PERSONA[r]).join(" · ")}
                  </span>
                  {o.comision !== null && (
                    <span className="badge badge-brand">Referente {o.comision.toFixed(2)}%</span>
                  )}
                  {o.pendiente && <span className="badge badge-warning">Pendiente</span>}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      {editando && <PersonaFormPanel persona={persona} onClose={() => setEditando(false)} />}

      {vinculando && (
        <VincularPersonaEmpresaPanel
          persona={{ id: persona.id, nombre }}
          onClose={() => setVinculando(false)}
        />
      )}

      {vinculandoObra && (
        <VincularObraPanel
          persona={{ id: persona.id, nombre }}
          onClose={() => setVinculandoObra(false)}
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
