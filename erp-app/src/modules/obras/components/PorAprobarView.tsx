"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowLeft, Link2, MapPin, UserRound } from "lucide-react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { labelRol } from "@/lib/entes";
import { formatFecha } from "@/lib/utils";
import { resolverObra } from "../actions";
import { ORIGEN, TIPO } from "../etiquetas";
import type { PorAprobar } from "../queries";
import { LABEL_ESTADO, resolverSchema, type Parecida, type ResolverForm } from "../types";

const COINCIDE = { nombre: "Nombre parecido", direccion: "Misma dirección" } as const;

function lugar(o: { direccion: string; localidad?: string | null }) {
  return o.localidad ? `${o.direccion}, ${o.localidad}` : o.direccion;
}

function RechazarModal({ obra, onClose }: { obra: PorAprobar; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<ResolverForm>({
    resolver: zodResolver(resolverSchema),
    defaultValues: { id: obra.id, decision: "rechazar", motivo: "" },
  });
  const error = formState.errors.motivo;

  async function onSubmit(data: ResolverForm) {
    setEnviando(true);
    const result = await resolverObra(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(obra.antes ? "Cambio rechazado" : "Obra rechazada");
    onClose();
  }

  return (
    <FormModal
      title={obra.antes ? "Rechazar el cambio" : "Rechazar la obra"}
      confirmLabel="Rechazar"
      peligro
      onClose={onClose}
      onSubmit={handleSubmit(onSubmit)}
      enviando={enviando}
      hayCambios={formState.isDirty}
    >
      <p className="t-body-m">
        {obra.antes
          ? `"${obra.nombre}" vuelve a "${obra.antes.nombre}", ${obra.antes.direccion}.`
          : `"${obra.nombre}" se desactiva.`}{" "}
        {obra.responsable} recibe el motivo.
      </p>
      <Campo id="rechazo-motivo" label="Motivo" requerido error={error}>
        <textarea id="rechazo-motivo" rows={3} aria-required className={claseInput(error)} {...register("motivo")} />
      </Campo>
    </FormModal>
  );
}

function Tarjeta({ obra }: { obra: PorAprobar }) {
  const [dialogo, setDialogo] = useState<"rechazar" | Parecida | null>(null);
  const [enviando, setEnviando] = useState(false);
  const esAlta = obra.antes === null;

  async function resolver(input: ResolverForm, ok: string) {
    setEnviando(true);
    const result = await resolverObra(input);
    setEnviando(false);
    if (!result.success) toast.error(result.error);
    else toast.success(ok);
  }

  const vinculos = obra.guardados.map((g) => `${g.nombre}${g.roles?.length ? ` (${g.roles.map((r) => labelRol("obra", r)).join(", ")})` : ""}`);

  return (
    <div className="card flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="t-h3 min-w-0 flex-1">{obra.nombre}</h2>
        <span className="badge badge-warning">{esAlta ? "Alta" : "Cambio"}</span>
      </div>
      <div className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
        <span className="flex items-center gap-1">
          <MapPin size={12} strokeWidth={1.75} />
          {lugar(obra)}
        </span>
        <span className="flex items-center gap-1" title="Responsable">
          <UserRound size={12} strokeWidth={1.75} />
          {obra.responsable} · {formatFecha(obra.created_at)}
        </span>
        <span>{TIPO[obra.tipo]}</span>
        <span>{ORIGEN[obra.origen]}</span>
        <span>{LABEL_ESTADO[obra.estado].label}</span>
      </div>
      {obra.antes && (
        <p className="t-body-m rounded-md bg-bg-subtle px-3 py-2">
          <span className="font-semibold">Antes: </span>
          {obra.antes.nombre}, {obra.antes.direccion}
        </p>
      )}
      {obra.notas && <p className="t-body-m whitespace-pre-wrap">{obra.notas}</p>}
      {vinculos.length > 0 && (
        <p className="t-caption flex items-center gap-1">
          <Link2 size={12} strokeWidth={1.75} className="shrink-0" />
          Al aprobarla se vincula {vinculos.join(", ")}.
        </p>
      )}

      <div>
        <p className="t-label mb-1">Se parece a</p>
        {obra.parecidas.length === 0 ? (
          <p className="t-caption">Ya no se parece a ninguna activa.</p>
        ) : (
          <ul className="flex flex-col rounded-lg border border-border">
            {obra.parecidas.map((p) => (
              <li key={p.id} className="row flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border last:border-b-0">
                <div className="min-w-0 flex-1">
                  <p className="t-body-m truncate font-medium">{p.nombre}</p>
                  <p className="t-caption truncate">
                    {p.direccion} · {p.responsable}
                  </p>
                </div>
                <span className="badge badge-neutral">{COINCIDE[p.coincide]}</span>
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

      <div className="flex justify-end gap-2">
        <button className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => setDialogo("rechazar")}>
          Rechazar
        </button>
        <button
          className="btn btn-primary btn-sm"
          disabled={enviando}
          onClick={() => resolver({ id: obra.id, decision: "aprobar" }, esAlta ? "Obra aprobada" : "Cambio aprobado")}
        >
          Aprobar
        </button>
      </div>

      {dialogo === "rechazar" && <RechazarModal obra={obra} onClose={() => setDialogo(null)} />}
      {dialogo !== null && dialogo !== "rechazar" && (
        <ConfirmModal
          title="Es la misma obra"
          mensaje={`"${obra.nombre}" se desactiva y ${obra.responsable} se suma a "${dialogo.nombre}" como participante${
            vinculos.length > 0 ? `, con ${vinculos.join(", ")}` : ""
          }. ${dialogo.responsable} recibe el aviso.`}
          confirmLabel="Es la misma"
          onConfirm={() => resolver({ id: obra.id, decision: "es_la_misma", existente: dialogo.id }, "Resuelta como la misma")}
          onClose={() => setDialogo(null)}
        />
      )}
    </div>
  );
}

export function PorAprobarView({ obras }: { obras: PorAprobar[] }) {
  return (
    <div className="flex flex-col gap-4">
      <Link href="/obras" className="t-body-m flex w-fit items-center gap-1 text-text-secondary hover:text-text-primary">
        <ArrowLeft size={14} />
        Obras
      </Link>
      {obras.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Nada por aprobar</p>
          <p className="t-body-m mt-1">Acá llegan las obras que se parecen a otra, hasta que las resuelvas.</p>
        </div>
      ) : (
        obras.map((o) => <Tarjeta key={o.id} obra={o} />)
      )}
    </div>
  );
}
