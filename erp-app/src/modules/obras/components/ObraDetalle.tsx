"use client";

import { useState } from "react";
import Link from "next/link";
import { Pencil, Plus, UserRoundCog } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { formatFechaHora } from "@/lib/utils";
import {
  desvincularEmpresa,
  desvincularPersona,
  quitarReferente,
  setActivoObra,
} from "../actions";
import {
  LABEL_ESTADO,
  LABEL_MOTIVO_PERDIDA,
  LABEL_ORIGEN,
  LABEL_PROVINCIA,
  LABEL_ROL_EMPRESA,
  LABEL_ROL_PERSONA,
  LABEL_TIPO,
  type Empresa,
  type Obra,
  type Usuario,
} from "../types";
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
  empresasDisponibles,
  usuarios,
  permisos,
}: {
  obra: Obra;
  responsable: Usuario | null;
  empresas: (VinculoEmpresa & { razon_social: string })[];
  personas: (VinculoPersona & { empresa: string | null })[];
  referentes: ReferenteVista[];
  transferencias: TransferenciaVista[];
  empresasDisponibles: Empresa[];
  usuarios: Usuario[];
  permisos: Permisos;
}) {
  const [editando, setEditando] = useState(false);
  const [vinculandoEmpresa, setVinculandoEmpresa] = useState<VinculoEmpresa | true | null>(null);
  const [vinculandoPersona, setVinculandoPersona] = useState<VinculoPersona | true | null>(null);
  const [editandoReferente, setEditandoReferente] = useState<ReferenteVista | true | null>(null);
  const [transfiriendo, setTransfiriendo] = useState(false);
  const [desactivando, setDesactivando] = useState(false);

  const comisionPorPersona = new Map(referentes.map((r) => [r.persona_id, r]));

  async function correr(accion: () => Promise<{ success: boolean; error?: string }>, ok: string) {
    const result = await accion();
    if (result.success) toast.success(ok);
    else toast.error(result.error);
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-2">
        <Link href="/obras" className="btn btn-ghost btn-sm">
          ← Obras
        </Link>
        <h2 className="t-h2 min-w-0 flex-1 truncate">{obra.nombre}</h2>
        {permisos.editar && (
          <button className="btn btn-secondary btn-sm" onClick={() => setEditando(true)}>
            <Pencil size={14} />
            Editar
          </button>
        )}
        {permisos.transferir && (
          <button className="btn btn-secondary btn-sm" onClick={() => setTransfiriendo(true)}>
            <UserRoundCog size={14} />
            Transferir
          </button>
        )}
        {permisos.desactivar && (
          <button className="btn btn-danger btn-sm" onClick={() => setDesactivando(true)}>
            Desactivar
          </button>
        )}
      </div>

      <DatosGenerales
        obra={obra}
        responsable={responsable}
        labels={{
          estado: LABEL_ESTADO,
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
          <p className="t-caption">Ninguna empresa vinculada todavía.</p>
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
                <span className="t-caption">
                  {e.roles.map((r) => LABEL_ROL_EMPRESA[r]).join(" · ")}
                </span>
                {permisos.vincular && (
                  <>
                    <button className="btn btn-ghost btn-sm" onClick={() => setVinculandoEmpresa(e)}>
                      Editar
                    </button>
                    <button
                      className="btn btn-ghost btn-sm"
                      onClick={() =>
                        correr(() => desvincularEmpresa(e.id, obra.id), "Empresa desvinculada")
                      }
                    >
                      Quitar
                    </button>
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <section>
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Personas</h3>
          {permisos.referentes && personas.length > 0 && (
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
          <p className="t-caption">Ninguna persona vinculada todavía.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {personas.map((p) => {
              const ref = comisionPorPersona.get(p.persona_id);
              return (
                <li key={p.id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                  <Link
                    href={`/obras/personas/${p.persona_id}`}
                    className="t-body-m min-w-0 flex-1 truncate font-semibold hover:underline"
                  >
                    {p.nombre}
                  </Link>
                  {p.empresa && <span className="t-caption">{p.empresa}</span>}
                  <span className="t-caption">
                    {p.roles.map((r) => LABEL_ROL_PERSONA[r]).join(" · ")}
                  </span>
                  {ref && (
                    <span className="badge badge-brand">
                      Referente {ref.porcentaje_comision.toFixed(2)}%
                    </span>
                  )}
                  {permisos.referentes && (
                    <button
                      className="btn btn-ghost btn-sm"
                      onClick={() =>
                        ref
                          ? correr(() => quitarReferente(ref.id, obra.id), "Referente quitado")
                          : setEditandoReferente(true)
                      }
                    >
                      {ref ? "Quitar referente" : "Referente"}
                    </button>
                  )}
                  {permisos.vincular && (
                    <>
                      <button className="btn btn-ghost btn-sm" onClick={() => setVinculandoPersona(p)}>
                        Editar
                      </button>
                      <button
                        className="btn btn-ghost btn-sm"
                        onClick={() =>
                          correr(() => desvincularPersona(p.id, obra.id), "Persona desvinculada")
                        }
                      >
                        Quitar
                      </button>
                    </>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {transferencias.length > 0 && (
        <section className="card p-4">
          <h3 className="t-h3 mb-3">Historial de responsables</h3>
          {/* La obra la ve su responsable actual, así que sin esto "¿por qué
              no la veo más?" no tiene respuesta dentro de la app. */}
          <ul className="flex flex-col gap-1">
            {transferencias.map((t) => (
              <li key={t.id} className="t-body-m">
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
          empresas={empresasDisponibles}
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
          personas={personas.map((p) => ({ id: p.persona_id, nombre: p.nombre }))}
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

      {desactivando && (
        <ConfirmModal
          title="Desactivar obra"
          mensaje="La obra deja de aparecer en el listado. Sus vínculos quedan intactos y se puede reactivar."
          onConfirm={() => correr(() => setActivoObra(obra.id, false), "Obra desactivada")}
          onClose={() => setDesactivando(false)}
        />
      )}
    </div>
  );
}
