"use client";

import { useState } from "react";
import Link from "next/link";
import { Archive, BadgePercent, Link2, Pencil, Plus, Unlink, UserRoundCog } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { formatFechaHora } from "@/lib/utils";
import { copiarEnlace } from "../copiarEnlace";
import {
  desvincularEmpresa,
  desvincularPersona,
  quitarReferente,
  setActivoObra,
} from "../actions";
import {
  BADGE_ESTADO,
  LABEL_ESTADO,
  LABEL_MOTIVO_PERDIDA,
  LABEL_ORIGEN,
  LABEL_PROVINCIA,
  LABEL_ROL_EMPRESA,
  LABEL_ROL_PERSONA,
  LABEL_TIPO,
  type Obra,
  type Usuario,
} from "../types";
import { EstadoPendiente } from "./EstadoPendiente";
import { ObraFormPanel } from "./ObraFormPanel";
import { ReferentePanel } from "./ReferentePanel";
import { TransferirPanel } from "./TransferirPanel";
import { VincularEmpresaPanel, type VinculoEmpresa } from "./VincularEmpresaPanel";
import { VincularPersonaPanel, type VinculoPersona } from "./VincularPersonaPanel";
import { DatosGenerales } from "./ObraDatosGenerales";

export type Permisos = {
  editar: boolean;
  vincular: boolean;
  referentes: boolean;
  transferir: boolean;
  desactivar: boolean;
  crearEmpresa: boolean;
  crearPersona: boolean;
};

export type TransferenciaVista = {
  id: string;
  created_at: string;
  de: string;
  a: string;
};

// Una sola confirmación por ficha: las acciones destructivas de las filas
// viven dentro de un `.map()`, así que lo que se confirma viaja en el estado
// en vez de tener un booleano por fila.
type Confirmacion = {
  title: string;
  mensaje: string;
  confirmLabel: string;
  accion: () => Promise<{ success: boolean; error?: string }>;
  ok: string;
};

export type ReferenteVista = {
  id: string;
  persona_id: string;
  porcentaje_comision: number;
  observaciones: string | null;
  nombre: string;
};

export function ObraDetalle({
  obra,
  responsable,
  empresas,
  personas,
  referentes,
  transferencias,
  usuarios,
  permisos,
}: {
  obra: Obra;
  responsable: Usuario | null;
  // `pendiente` no vive en el tipo del panel de vinculación: ahí no se usa, y
  // acá es lo que distingue un vínculo real de uno que todavía espera.
  empresas: (VinculoEmpresa & { razon_social: string; pendiente: boolean })[];
  personas: (VinculoPersona & { empresa: string | null; pendiente: boolean })[];
  referentes: ReferenteVista[];
  transferencias: TransferenciaVista[];
  usuarios: Usuario[];
  permisos: Permisos;
}) {
  const [editando, setEditando] = useState(false);
  const [vinculandoEmpresa, setVinculandoEmpresa] = useState<VinculoEmpresa | true | null>(null);
  const [vinculandoPersona, setVinculandoPersona] = useState<VinculoPersona | true | null>(null);
  const [editandoReferente, setEditandoReferente] = useState<ReferenteVista | true | null>(null);
  const [transfiriendo, setTransfiriendo] = useState(false);
  const [confirmando, setConfirmando] = useState<Confirmacion | null>(null);

  const comisionPorPersona = new Map(referentes.map((r) => [r.persona_id, r]));

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
          <Link href="/obras" className="btn btn-ghost btn-sm shrink-0">
            ← Obras
          </Link>
          <h2 className="t-h2 min-w-0 flex-1 truncate">{obra.nombre}</h2>
          {/* El listado codifica el estado por color y la ficha lo bajaba a un
              `dt/dd` gris. Pendiente no se repite acá: `EstadoPendiente` ya
              pone el bloque completo dos renglones abajo. */}
          <span className={`badge shrink-0 ${BADGE_ESTADO[obra.estado]}`}>
            {LABEL_ESTADO[obra.estado]}
          </span>
        </div>
        {/* Editar es la acción de la ficha y queda a la vista; el resto va al
            menú. Desactivar en rojo sólido acá era el elemento más brillante
            de la pantalla, por encima del nombre de la obra. */}
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
                onClick: () => copiarEnlace(`/obras/${obra.id}`),
              },
              ...(permisos.transferir
                ? [
                    {
                      label: "Transferir",
                      icon: <UserRoundCog size={14} strokeWidth={1.75} />,
                      onClick: () => setTransfiriendo(true),
                    },
                  ]
                : []),
              ...(permisos.desactivar
                ? [
                    {
                      label: "Desactivar obra",
                      icon: <Archive size={14} strokeWidth={1.75} />,
                      onClick: () =>
                        setConfirmando({
                          title: "Desactivar obra",
                          mensaje:
                            "La obra deja de aparecer en el listado. Sus vínculos quedan intactos y se puede reactivar.",
                          confirmLabel: "Desactivar",
                          accion: () => setActivoObra(obra.id, false),
                          ok: "Obra desactivada",
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
        pendiente={obra.pendiente}
        motivoRechazo={obra.motivo_rechazo}
        queEs="Esta obra"
        detalle="Se parece a una que ya existe. Hasta que la autoricen no se le pueden vincular empresas ni personas."
      />

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

      <section>
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Empresas</h3>
          {permisos.vincular && (
            <button className="btn btn-secondary btn-sm" onClick={() => setVinculandoEmpresa(true)}>
              <Plus size={14} />
              Vincular
            </button>
          )}
        </div>
        {empresas.length === 0 ? (
          <div className="empty-state p-8">
            <p className="t-body-m">Ninguna empresa vinculada todavía.</p>
          </div>
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
                    <span className="t-caption">
                      {e.roles.map((r) => LABEL_ROL_EMPRESA[r]).join(" · ")}
                    </span>
                    {e.pendiente && <span className="badge badge-warning">Pendiente</span>}
                  </div>
                </div>
                {permisos.vincular && (
                  <OverflowMenu
                    items={[
                      {
                        label: "Editar vínculo",
                        icon: <Pencil size={14} strokeWidth={1.75} />,
                        onClick: () => setVinculandoEmpresa(e),
                      },
                      {
                        label: "Quitar de la obra",
                        icon: <Unlink size={14} strokeWidth={1.75} />,
                        onClick: () =>
                          setConfirmando({
                            title: "Quitar empresa de la obra",
                            mensaje: `«${e.razon_social}» deja de figurar en esta obra. Se pierden los roles y las observaciones del vínculo. La empresa sigue existiendo.`,
                            confirmLabel: "Quitar",
                            accion: () => desvincularEmpresa(e.id, obra.id),
                            ok: "Empresa desvinculada",
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
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Personas</h3>
          {/* Referente solo de gente ya vinculada y autorizada: la fila de
              referente también da acceso al contacto, y la base la corta con
              OB019 si el vínculo todavía está pendiente. */}
          {permisos.referentes && personas.some((p) => !p.pendiente) && (
            <button className="btn btn-secondary btn-sm" onClick={() => setEditandoReferente(true)}>
              Marcar referente
            </button>
          )}
          {permisos.vincular && (
            <button className="btn btn-secondary btn-sm" onClick={() => setVinculandoPersona(true)}>
              <Plus size={14} />
              Vincular
            </button>
          )}
        </div>
        {personas.length === 0 ? (
          <div className="empty-state p-8">
            <p className="t-body-m">Ninguna persona vinculada todavía.</p>
          </div>
        ) : (
          <ul className="flex flex-col gap-2">
            {personas.map((p) => {
              const ref = comisionPorPersona.get(p.persona_id);
              const acciones = [
                ...(permisos.referentes && !p.pendiente
                  ? [
                      {
                        label: ref ? "Quitar referente" : "Marcar referente",
                        icon: <BadgePercent size={14} strokeWidth={1.75} />,
                        onClick: () =>
                          ref
                            ? setConfirmando({
                                title: "Quitar referente",
                                mensaje: `Se borra la comisión de ${ref.porcentaje_comision.toFixed(2)}% y sus observaciones. «${p.nombre}» sigue vinculada a la obra.`,
                                confirmLabel: "Quitar",
                                accion: () => quitarReferente(ref.id, obra.id),
                                ok: "Referente quitado",
                              })
                            : setEditandoReferente(true),
                      },
                    ]
                  : []),
                ...(permisos.vincular
                  ? [
                      {
                        label: "Editar vínculo",
                        icon: <Pencil size={14} strokeWidth={1.75} />,
                        onClick: () => setVinculandoPersona(p),
                      },
                      {
                        label: "Quitar de la obra",
                        icon: <Unlink size={14} strokeWidth={1.75} />,
                        onClick: () =>
                          setConfirmando({
                            title: "Quitar persona de la obra",
                            mensaje: `«${p.nombre}» deja de figurar en esta obra. Se pierden los roles y las observaciones del vínculo. La persona sigue existiendo.`,
                            confirmLabel: "Quitar",
                            accion: () => desvincularPersona(p.id, obra.id),
                            ok: "Persona desvinculada",
                          }),
                        destructive: true,
                      },
                    ]
                  : []),
              ];
              return (
                <li key={p.id} className="card flex items-center gap-3 p-3">
                  <div className="min-w-0 flex-1">
                    <Link
                      href={`/obras/personas/${p.persona_id}`}
                      className="t-body-m block truncate font-semibold hover:underline"
                    >
                      {p.nombre}
                    </Link>
                    <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
                      {p.empresa && <span className="t-caption">{p.empresa}</span>}
                      <span className="t-caption">
                        {p.roles.map((r) => LABEL_ROL_PERSONA[r]).join(" · ")}
                      </span>
                      {/* El vínculo pendiente no abre la ficha de contacto: hasta
                          que lo autoricen, la persona ajena sigue siendo ajena. */}
                      {p.pendiente && <span className="badge badge-warning">Pendiente</span>}
                      {ref && (
                        <span className="badge badge-brand">
                          Referente {ref.porcentaje_comision.toFixed(2)}%
                        </span>
                      )}
                    </div>
                  </div>
                  {acciones.length > 0 && <OverflowMenu items={acciones} />}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {transferencias.length > 0 && (
        <section>
          <h3 className="t-h3 mb-2">Historial de responsables</h3>
          {/* La obra la ve su responsable actual, así que sin esto "¿por qué
              no la veo más?" no tiene respuesta dentro de la app. */}
          <ul className="card flex flex-col p-4">
            {transferencias.map((t) => (
              <li
                key={t.id}
                className="t-body-m border-b border-border py-2 first:pt-0 last:border-b-0 last:pb-0"
              >
                <span className="t-caption">{formatFechaHora(t.created_at)}</span> — de{" "}
                <span className="font-semibold">{t.de}</span> a{" "}
                <span className="font-semibold">{t.a}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {editando && <ObraFormPanel obra={obra} onClose={() => setEditando(false)} />}

      {vinculandoEmpresa && (
        <VincularEmpresaPanel
          obraId={obra.id}
          vinculo={vinculandoEmpresa === true ? undefined : vinculandoEmpresa}
          puedeCrearEmpresa={permisos.crearEmpresa}
          onClose={() => setVinculandoEmpresa(null)}
        />
      )}

      {vinculandoPersona && (
        <VincularPersonaPanel
          obraId={obra.id}
          empresas={empresas.map((e) => ({ id: e.empresa_id, razon_social: e.razon_social }))}
          vinculo={vinculandoPersona === true ? undefined : vinculandoPersona}
          puedeCrearPersona={permisos.crearPersona}
          onClose={() => setVinculandoPersona(null)}
        />
      )}

      {editandoReferente && (
        <ReferentePanel
          obraId={obra.id}
          personas={personas
            .filter((p) => !p.pendiente)
            .map((p) => ({ id: p.persona_id, nombre: p.nombre }))}
          referente={editandoReferente === true ? undefined : editandoReferente}
          onClose={() => setEditandoReferente(null)}
        />
      )}

      {transfiriendo && (
        <TransferirPanel
          obraId={obra.id}
          obraNombre={obra.nombre}
          responsableActual={responsable?.nombre ?? null}
          usuarios={usuarios}
          onClose={() => setTransfiriendo(false)}
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
