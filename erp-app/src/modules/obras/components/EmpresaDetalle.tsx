"use client";

import { useState } from "react";
import Link from "next/link";
import { Archive, Link2, Pencil, Plus, Unlink, UserRoundCog } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { desactivarEmpresa, desvincularPersonaEmpresa } from "../actions";
import { copiarEnlace } from "../copiarEnlace";
import {
  LABEL_ESTADO,
  LABEL_PROVINCIA,
  LABEL_ROL_EMPRESA,
  type EmpresaFicha,
  type EstadoObra,
  type RolEmpresa,
  type Usuario,
} from "../types";
import { Breadcrumb } from "./Breadcrumb";
import { Dato, Observaciones } from "./Dato";
import { EmpresaFormPanel } from "./EmpresaFormPanel";
import { EstadoPendiente } from "./EstadoPendiente";
import { TransferirEntidadPanel } from "./TransferirEntidadPanel";
import { VincularObraPanel } from "./VincularObraPanel";
import { VincularPersonaEmpresaPanel } from "./VincularPersonaEmpresaPanel";

// Misma forma que ObraDetalle y PersonaDetalle: la acción destructiva de la
// fila vive dentro de un `.map()`, así que lo que se confirma viaja en el
// estado en vez de tener un booleano por fila.
type Confirmacion = {
  title: string;
  mensaje: string;
  confirmLabel: string;
  accion: () => Promise<{ success: boolean; error?: string }>;
  ok: string;
};

export function EmpresaDetalle({
  empresa,
  personas,
  obras,
  permisos,
  duenio,
  puedeTransferir,
  usuarios,
  seccionTareas,
}: {
  empresa: EmpresaFicha;
  personas: { id: string; persona_id: string; nombre: string; cargo: string | null; es_principal: boolean }[];
  obras: {
    id: string;
    obra_id: string;
    nombre: string;
    estado: EstadoObra;
    localidad: string | null;
    roles: RolEmpresa[];
  }[];
  // Vincular personas y vincular obras son dos permisos distintos porque son
  // dos tablas distintas: `obras_personas_empresas` y `obras_vincular`.
  permisos: { editar: boolean; vincularPersona: boolean; vincularObra: boolean };
  // null = sin la vista de Tareas: la sección no se muestra.
  seccionTareas: React.ReactNode;
  // El nombre del dueño lo resuelve la page: es lo que el panel de
  // transferencia muestra arriba de todo.
  duenio: string | null;
  puedeTransferir: boolean;
  usuarios: Usuario[];
}) {
  const [editando, setEditando] = useState(false);
  const [confirmando, setConfirmando] = useState<Confirmacion | null>(null);
  const [vinculandoPersona, setVinculandoPersona] = useState(false);
  const [vinculandoObra, setVinculandoObra] = useState(false);
  const [transfiriendo, setTransfiriendo] = useState(false);

  const congelada = empresa.pendiente;

  async function correr(accion: () => Promise<{ success: boolean; error?: string }>, ok: string) {
    const result = await accion();
    if (result.success) toast.success(ok);
    else toast.error(result.error);
  }

  return (
    <div className="flex flex-col gap-6">
      {/* Abajo de `sm` el título va en su propia línea: compartiendo la fila
          con las acciones se comía hasta quedar en una letra, y "Desactivar"
          quedaba arriba del nombre de lo que se está mirando. */}
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
        <div className="flex min-w-0 items-center gap-2 sm:flex-1">
          <Breadcrumb padre="Empresas" href="/obras/empresas" actual={empresa.razon_social} />
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
              ...(puedeTransferir
                ? [
                    {
                      label: "Transferir",
                      icon: <UserRoundCog size={14} strokeWidth={1.75} />,
                      onClick: () => setTransfiriendo(true),
                    },
                  ]
                : []),
              ...(permisos.editar
                ? [
                    {
                      label: "Desactivar empresa",
                      icon: <Archive size={14} strokeWidth={1.75} />,
                      onClick: () =>
                        setConfirmando({
                          title: "Desactivar empresa",
                          mensaje:
                            "Si participa en alguna obra activa —incluidas obras que no ves— la base lo va a impedir. Desvinculala primero.",
                          confirmLabel: "Desactivar",
                          accion: () => desactivarEmpresa(empresa.id),
                          ok: "Empresa desactivada",
                        }),
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
          <Dato
            etiqueta="Teléfono"
            valor={
              empresa.telefono && (
                <a href={`tel:${empresa.telefono}`} className="hover:underline">
                  {empresa.telefono}
                </a>
              )
            }
          />
          <Dato
            etiqueta="Email"
            valor={
              empresa.email && (
                <a href={`mailto:${empresa.email}`} className="hover:underline">
                  {empresa.email}
                </a>
              )
            }
          />
          {/* El campo es texto libre: sin esquema el href quedaría relativo
              a /obras y el link llevaría adentro de la app. */}
          <Dato
            etiqueta="Website"
            valor={
              empresa.website && (
                <a
                  href={/^https?:\/\//i.test(empresa.website) ? empresa.website : `https://${empresa.website}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:underline"
                >
                  {empresa.website}
                </a>
              )
            }
          />
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
        <div className="mb-2 flex flex-wrap items-center gap-2">
          <h3 className="t-h3 min-w-0 flex-1">Personas</h3>
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
              <li key={p.id} className="card flex items-center gap-3 p-3">
                <div className="min-w-0 flex-1">
                  <Link
                    href={`/obras/personas/${p.persona_id}?ctx=empresa:${empresa.id}`}
                    className="t-body-m block truncate font-semibold hover:underline"
                  >
                    {p.nombre}
                  </Link>
                  <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
                    {p.cargo && <span className="t-caption">{p.cargo}</span>}
                    {p.es_principal && <span className="badge badge-neutral">Principal</span>}
                  </div>
                </div>
                {permisos.vincularPersona && (
                  <OverflowMenu
                    items={[
                      {
                        label: "Quitar de la empresa",
                        icon: <Unlink size={14} strokeWidth={1.75} />,
                        onClick: () =>
                          setConfirmando({
                            title: "Quitar de la empresa",
                            mensaje: `«${p.nombre}» deja de figurar en «${empresa.razon_social}». Se pierde el cargo. Las dos fichas siguen existiendo.`,
                            confirmLabel: "Quitar",
                            accion: () =>
                              desvincularPersonaEmpresa(p.id, p.persona_id, empresa.id),
                            ok: "Vínculo quitado",
                          }),
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
        <div className="mb-2 flex flex-wrap items-center gap-2">
          <h3 className="t-h3 min-w-0 flex-1">Obras</h3>
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
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      {seccionTareas}

      {editando && <EmpresaFormPanel empresa={empresa} onClose={() => setEditando(false)} />}

      {transfiriendo && (
        <TransferirEntidadPanel
          tipo="empresa"
          id={empresa.id}
          nombre={empresa.razon_social}
          duenioActual={duenio}
          usuarios={usuarios}
          onClose={() => setTransfiriendo(false)}
        />
      )}

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

      {confirmando && (
        <ConfirmModal
          title={confirmando.title}
          mensaje={confirmando.mensaje}
          confirmLabel={confirmando.confirmLabel}
          onConfirm={() => correr(confirmando.accion, confirmando.ok)}
          onClose={() => setConfirmando(null)}
        />
      )}
    </div>
  );
}
