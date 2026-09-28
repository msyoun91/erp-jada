"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowLeft, Eye, Link2, UserRound } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { labelRol } from "@/lib/entes";
import { formatFecha } from "@/lib/utils";
import { resolverContacto, verContacto } from "../actions";
import type { PorAprobar } from "../queries";
import { resolverSchema, type DatosContacto, type Guardado, type Parecida, type ResolverForm } from "../types";
import { IconoContacto } from "./Buscador";
import { COINCIDE } from "./Parecidas";

function textoGuardado(g: Guardado) {
  if (g.empresa) return `a ${g.empresa}${g.cargo ? ` como ${g.cargo}` : ""}`;
  const roles = (g.roles ?? []).map((r) => labelRol(g.ente ?? "", r)).join(", ");
  return `a ${g.registro ?? "un registro"}${roles ? ` como ${roles}` : ""}`;
}

function RechazarModal({ c, onClose }: { c: PorAprobar; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<ResolverForm>({
    resolver: zodResolver(resolverSchema),
    defaultValues: { tipo: c.tipo, id: c.id, decision: "rechazar", motivo: "" },
  });
  const error = formState.errors.motivo;

  async function onSubmit(data: ResolverForm) {
    setEnviando(true);
    const result = await resolverContacto(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(c.antes ? "Cambio rechazado" : "Rechazada");
    onClose();
  }

  return (
    <FormModal
      title={c.antes ? "Rechazar el cambio" : `Rechazar ${c.tipo === "persona" ? "la persona" : "la empresa"}`}
      confirmLabel="Rechazar"
      peligro
      onClose={onClose}
      onSubmit={handleSubmit(onSubmit)}
      enviando={enviando}
      hayCambios={formState.isDirty}
    >
      <p className="t-body-m">
        {c.antes ? "Los datos vuelven a como estaban aprobados." : `"${c.nombre}" se desactiva.`} {c.dueno} recibe el motivo.
      </p>
      <Campo id="rechazo-motivo" label="Motivo" requerido error={error}>
        <textarea id="rechazo-motivo" rows={3} aria-required className={claseInput(error)} {...register("motivo")} />
      </Campo>
    </FormModal>
  );
}

function Tarjeta({ c }: { c: PorAprobar }) {
  const [dialogo, setDialogo] = useState<"rechazar" | Parecida | null>(null);
  const [vincular, setVincular] = useState(true);
  const [contacto, setContacto] = useState<DatosContacto | null>(null);
  const [enviando, setEnviando] = useState(false);
  const esAlta = c.antes === null;
  const persona = c.tipo === "persona";
  // CO023: con el mismo teléfono o email es la misma persona, no se aprueba.
  const mismoDato = persona && c.parecidas.some((p) => p.coincide.some((x) => x !== "nombre"));
  const conRegistro = c.guardados.filter((g) => g.registro !== null);

  async function resolver(input: ResolverForm, ok: string) {
    setEnviando(true);
    const result = await resolverContacto(input);
    setEnviando(false);
    if (!result.success) toast.error(result.error);
    else toast.success(ok);
  }

  async function ver() {
    const r = await verContacto(c.id);
    if (!r.success) toast.error(r.error);
    else setContacto(r.contacto);
  }

  return (
    <div className="card flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <IconoContacto tipo={c.tipo} />
        <h2 className="t-h3 min-w-0 flex-1">{c.nombre}</h2>
        <span className="badge badge-warning">{esAlta ? "Alta" : "Cambio"}</span>
      </div>
      <div className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
        <span className="flex items-center gap-1" title={persona ? "Dueño" : "La cargó"}>
          <UserRound size={12} strokeWidth={1.75} />
          {c.dueno}
          {c.equipo && ` · ${c.equipo}`} · {formatFecha(c.created_at)}
        </span>
        {persona &&
          (contacto ? (
            <span>
              {[contacto.telefono, contacto.email].filter(Boolean).join(" · ") || "Sin teléfono ni email"}
            </span>
          ) : (
            <button className="btn btn-ghost btn-sm" onClick={ver}>
              <Eye size={14} />
              Ver contacto
            </button>
          ))}
      </div>
      {c.antes && c.antes.nombre !== c.nombre && (
        <p className="t-body-m rounded-md bg-bg-subtle px-3 py-2">
          <span className="font-semibold">Antes: </span>
          {c.antes.nombre}
        </p>
      )}
      {c.antes && c.antes.nombre === c.nombre && <p className="t-caption">Cambió el teléfono o el email.</p>}
      {c.notas && <p className="t-body-m whitespace-pre-wrap">{c.notas}</p>}
      {c.guardados.length > 0 && (
        <p className="t-caption flex items-center gap-1">
          <Link2 size={12} strokeWidth={1.75} className="shrink-0" />
          Al aprobarla se vincula {c.guardados.map(textoGuardado).join("; ")}.
        </p>
      )}

      <div>
        <p className="t-label mb-1">Se parece a</p>
        {c.parecidas.length === 0 ? (
          <p className="t-caption">Ya no se parece a ninguna activa.</p>
        ) : (
          <ul className="flex flex-col rounded-lg border border-border">
            {c.parecidas.map((p) => (
              <li key={p.id} className="row flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border last:border-b-0">
                <div className="min-w-0 flex-1">
                  <p className="t-body-m truncate font-medium">{p.nombre}</p>
                  <p className="t-caption truncate">
                    {p.dueno}
                    {p.equipo && ` · ${p.equipo}`}
                  </p>
                </div>
                <span className="badge badge-neutral">{p.coincide.map((x) => COINCIDE[x]).join(", ")}</span>
                {esAlta && (
                  <button className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => setDialogo(p)}>
                    Es la misma
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex flex-wrap items-center justify-end gap-2">
        {mismoDato && <p className="t-caption flex-1">Con el mismo teléfono o email es la misma persona: no se aprueba.</p>}
        <button className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => setDialogo("rechazar")}>
          Rechazar
        </button>
        <button
          className="btn btn-primary btn-sm"
          disabled={enviando || mismoDato}
          onClick={() => resolver({ tipo: c.tipo, id: c.id, decision: "aprobar" }, esAlta ? "Aprobada" : "Cambio aprobado")}
        >
          Aprobar
        </button>
      </div>

      {dialogo === "rechazar" && <RechazarModal c={c} onClose={() => setDialogo(null)} />}
      {dialogo !== null && dialogo !== "rechazar" && (
        <ConfirmModal
          title="Es la misma"
          mensaje={`"${c.nombre}" se desactiva; queda "${dialogo.nombre}", de ${dialogo.dueno}.`}
          confirmLabel="Es la misma"
          onConfirm={() =>
            resolver(
              { tipo: c.tipo, id: c.id, decision: "es_la_misma", existente: dialogo.id, vincular: conRegistro.length > 0 && vincular },
              "Resuelta como la misma"
            )
          }
          onClose={() => setDialogo(null)}
        >
          {conRegistro.length > 0 && (
            <label className="t-body-m flex items-start gap-2">
              <input type="checkbox" className="mt-1" checked={vincular} onChange={(e) => setVincular(e.target.checked)} />
              Vincular &quot;{dialogo.nombre}&quot; {conRegistro.map(textoGuardado).join("; ")}, a nombre de {c.dueno}
            </label>
          )}
        </ConfirmModal>
      )}
    </div>
  );
}

export function PorAprobarView({ contactos }: { contactos: PorAprobar[] }) {
  return (
    <div className="flex flex-col gap-4">
      <Link href="/contactos" className="t-body-m flex w-fit items-center gap-1 text-text-secondary hover:text-text-primary">
        <ArrowLeft size={14} />
        Contactos
      </Link>
      {contactos.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Nada por aprobar</p>
          <p className="t-body-m mt-1">Acá llegan las personas y empresas que se parecen a otra, hasta que las resuelvas.</p>
        </div>
      ) : (
        contactos.map((c) => <Tarjeta key={`${c.tipo}-${c.id}`} c={c} />)
      )}
    </div>
  );
}
