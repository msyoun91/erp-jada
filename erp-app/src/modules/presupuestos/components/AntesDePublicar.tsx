"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { CircleCheck, TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { formatMonto } from "@/lib/monedas";
import { formatFecha, hace } from "@/lib/utils";
import { autorizarPedido, devolverPedido, pedirAutorizacion, publicarVersion, retirarVersion } from "../actions";
import type { AntesDePublicar as Antes } from "../queries";
import {
  devolverSchema,
  formatAlicuota,
  type AutorizacionVersion,
  type DevolverForm,
  type PedidoComercial,
} from "../types";

type Confirmar = { titulo: string; mensaje: string; boton: string; accion: () => Promise<void> };

const ESTADO = {
  pendiente: { label: "Pendiente", badge: "badge-warning" },
  autorizada: { label: "Autorizada", badge: "badge-success" },
} as const;

// Lo que autoriza Técnica, acá y en Revisión técnica (`presupuestos_pedido_resolver`, `presupuestos_tecnica_cubre`).
export const AUTORIZAR_TECNICA = "Autoriza también las ventanas iguales de esta versión, y vale para esta ventana mientras no cambie.";

// Lo que frena, lo que pide autorización y en qué está, y el paso que sigue: pedir o publicar en borrador; en revisión,
// autorizar o devolver quien puede, y retirar o publicar quien arma (decisiones/presupuestos.md → *Pantallas*).
export function AntesDePublicar({
  versionId,
  numero,
  estado,
  antes,
  nombres,
  yo,
}: {
  versionId: string;
  numero: number;
  estado: "borrador" | "en_revision";
  antes: Antes;
  nombres: Record<string, string>;
  yo: string;
}) {
  const [confirmar, setConfirmar] = useState<Confirmar | null>(null);
  const [devolviendo, setDevolviendo] = useState<string | null>(null);
  const { arma, frena, autorizaciones, resuelve, devuelta, plazo } = antes;
  // Los nombres salen de `obras_nombres`: quien autoriza sin figurar en la obra no está, y se omite.
  const por = (id: string | null) => {
    const nombre = id === yo ? "vos" : id && nombres[id];
    return nombre ? ` por ${nombre}` : "";
  };
  const borrador = estado === "borrador";
  const faltaPedir = autorizaciones.some((a) => a.estado === null);
  const esperan = autorizaciones.filter((a) => a.estado === "pendiente").length;

  async function hacer(r: Promise<{ success: true } | { success: false; error: string }>, ok: string) {
    const res = await r;
    if (!res.success) toast.error(res.error);
    else toast.success(ok);
  }

  const publicar = () =>
    setConfirmar({
      titulo: `Publicar la versión ${numero}`,
      mensaje: `La ve el cliente${plazo ? ` y vence en ${plazo} ${plazo === 1 ? "día" : "días"}` : ""}. Si la variante ya tenía una publicada, queda reemplazada.`,
      boton: "Publicar",
      accion: () => hacer(publicarVersion(versionId), `Versión ${numero} publicada`),
    });

  const pedir = () =>
    setConfirmar({
      titulo: "Pedir autorización",
      mensaje:
        "Pasa a revisión y no se edita hasta que autoricen o la retires. A quienes autorizan les llega un aviso. Lo que puedas autorizar vos queda autorizado, y si no espera nada más, se publica.",
      boton: "Pedir",
      accion: async () => {
        const r = await pedirAutorizacion(versionId);
        if (!r.success) toast.error(r.error);
        else if (r.estado === "publicado") toast.success(`Autorizada por vos y publicada: versión ${numero}`);
        else toast.success("Pedida: a quienes autorizan les llega un aviso");
      },
    });

  const retirar = () =>
    setConfirmar({
      titulo: "Retirar de revisión",
      mensaje:
        "Vuelve a borrador para editarla, sin aviso. Lo pendiente queda retirado y lo que autorizó el jefe deja de valer; lo de Técnica sigue para las ventanas que no cambien.",
      boton: "Retirar",
      accion: () => hacer(retirarVersion(versionId), `Versión ${numero} de vuelta en borrador`),
    });

  const autorizar = (a: AutorizacionVersion) =>
    setConfirmar({
      titulo: a.tipo === "comercial" ? "Autorizar" : `Autorizar ${a.pedido.etiqueta}`,
      mensaje:
        a.tipo === "comercial"
          ? "Autorizás lo que se pidió, como se ve arriba. Cuando no espere nada más, a quien la pidió le llega un aviso para publicarla."
          : AUTORIZAR_TECNICA,
      boton: "Autorizar",
      accion: () => hacer(autorizarPedido(a.id ?? ""), "Autorizada"),
    });

  const botones: React.ReactNode[] = [];
  if (arma && borrador) {
    botones.push(
      <button key="paso" className="btn btn-primary" disabled={frena.length > 0} onClick={faltaPedir ? pedir : publicar}>
        {faltaPedir ? "Pedir autorización" : "Publicar"}
      </button>,
    );
  }
  if (arma && !borrador) {
    botones.push(
      <button key="retirar" className="btn btn-secondary" onClick={retirar}>
        Retirar de revisión
      </button>,
      <button key="publicar" className="btn btn-primary" disabled={esperan > 0 || frena.length > 0} onClick={publicar}>
        Publicar
      </button>,
    );
  }

  return (
    <section data-tour="presupuestos_version_publicar" className="card flex flex-col gap-3" aria-label="Antes de publicar">
      <h3 className="t-h3">Antes de publicar</h3>

      {devuelta && (
        <div className="alert alert-warning">
          <p className="font-semibold">
            Devuelta{por(devuelta.resuelto_por)}
            {devuelta.resuelto_en && ` el ${formatFecha(devuelta.resuelto_en)}`}
          </p>
          <p>{devuelta.motivo}</p>
        </div>
      )}

      {frena.length > 0 && (
        <ul className="flex flex-col gap-1" aria-label="Lo que frena">
          {frena.map((f) => (
            <li key={f} className="t-body-m flex items-start gap-2 text-warning-text">
              <TriangleAlert size={16} className="mt-0.5 shrink-0" />
              {f}
            </li>
          ))}
        </ul>
      )}

      {autorizaciones.length === 0
        ? arma &&
          borrador &&
          frena.length === 0 && (
            <p className="t-body-m flex items-center gap-2 text-success-text">
              <CircleCheck size={16} />
              Nada pide autorización: se puede publicar.
            </p>
          )
        : (
            <ul className="flex flex-col">
              {autorizaciones.map((a, n) => (
                <li key={a.id ?? n} className="row flex flex-col gap-1 border-b border-border last:border-b-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="t-body-m min-w-0 flex-1 font-medium text-text-primary">
                      {a.tipo === "comercial" ? "Del jefe comercial" : `De Técnica · ${a.pedido.etiqueta}`}
                    </p>
                    {a.estado ? (
                      <span className={`badge ${ESTADO[a.estado].badge}`}>{ESTADO[a.estado].label}</span>
                    ) : (
                      <span className="badge badge-neutral">Falta pedirla</span>
                    )}
                  </div>
                  {a.tipo === "comercial" ? (
                    <Comercial pedido={a.pedido} />
                  ) : (
                    a.pedido.motivos.map((m) => (
                      <p key={m} className="t-caption flex items-start gap-1 text-warning-text">
                        <TriangleAlert size={12} className="mt-0.5 shrink-0" />
                        {m}
                      </p>
                    ))
                  )}
                  {a.estado === "pendiente" && a.pedido_en && (
                    <p className="t-caption">
                      Pedida{por(a.pedido_por)} · {hace(a.pedido_en)}
                    </p>
                  )}
                  {a.estado === "autorizada" && a.resuelto_en && (
                    <p className="t-caption">
                      Autorizada{por(a.resuelto_por)} el {formatFecha(a.resuelto_en)}
                    </p>
                  )}
                  {a.estado === "pendiente" && a.id && resuelve.includes(a.tipo) && (
                    <div className="mt-1 flex flex-wrap gap-2">
                      <button className="btn btn-primary btn-sm" onClick={() => autorizar(a)}>
                        Autorizar
                      </button>
                      <button className="btn btn-secondary btn-sm" onClick={() => setDevolviendo(a.id)}>
                        Devolver
                      </button>
                    </div>
                  )}
                </li>
              ))}
            </ul>
          )}

      {!borrador && esperan === 0 && frena.length === 0 && (
        <p className="t-body-m flex items-center gap-2 text-success-text">
          <CircleCheck size={16} />
          Autorizaron todo: lista para publicar.
        </p>
      )}

      {botones.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          {botones}
          {frena.length > 0 && (
            <p className="t-caption">
              {borrador ? "Para seguir, resolvé lo que frena." : "Para publicar, retirala y resolvé lo que frena."}
            </p>
          )}
          {frena.length === 0 && !borrador && esperan > 0 && (
            <p className="t-caption">
              {esperan === 1 ? "Espera 1 autorización." : `Espera ${esperan} autorizaciones.`}
            </p>
          )}
        </div>
      )}

      {confirmar && (
        <ConfirmModal
          title={confirmar.titulo}
          mensaje={confirmar.mensaje}
          confirmLabel={confirmar.boton}
          onClose={() => setConfirmar(null)}
          onConfirm={confirmar.accion}
        />
      )}
      {devolviendo && <DevolverModal id={devolviendo} onClose={() => setDevolviendo(null)} />}
    </section>
  );
}

const signo = (n: number) => (n > 0 ? "+ " : n < 0 ? "− " : "");

function Comercial({ pedido: p }: { pedido: PedidoComercial }) {
  return (
    <div className="flex flex-col gap-1">
      {p.descuento !== null && (
        <p className="t-body-m">
          Descuento de {formatAlicuota(p.descuento)}, sobre el tope de {formatAlicuota(p.tope)}
        </p>
      )}
      {p.renglones.length > 0 && (
        <>
          <p className="t-body-m">
            {p.renglones.length === 1 ? "1 renglón mantenido" : `${p.renglones.length} renglones mantenidos`}
            {p.diferencia.length > 0 &&
              ` · a hoy, ${p.diferencia.map((d) => `${signo(d.monto)}${formatMonto(Math.abs(d.monto), d.moneda)}`).join(" · ")}`}
          </p>
          <details>
            <summary className="t-caption cursor-pointer">Ver los renglones (sin IVA)</summary>
            <ul className="mt-1 flex flex-col gap-1">
              {p.renglones.map((r) => (
                <li key={r.renglon_id} className="t-caption flex justify-between gap-3 pl-3">
                  <span className="min-w-0">
                    {r.etiqueta}
                    {r.condiciones_en && ` · precios del ${formatFecha(r.condiciones_en)}`}
                    {" · "}
                    {r.precio === null ? "sin precio" : formatMonto(r.precio, r.moneda)}
                    {r.hoy === null ? ", hoy sin precio" : `, hoy ${formatMonto(r.hoy, r.moneda)}`}
                    {r.cantidad !== 1 && ` · × ${r.cantidad.toLocaleString("es-AR")}`}
                  </span>
                  {r.diferencia !== null && (
                    <span className="shrink-0 tabular-nums">
                      {signo(r.diferencia)}
                      {formatMonto(Math.abs(r.diferencia), r.moneda)}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          </details>
        </>
      )}
    </div>
  );
}

export function DevolverModal({
  id,
  ejemplo = "Ej: el descuento va hasta 8 %",
  onClose,
}: {
  id: string;
  ejemplo?: string;
  onClose: () => void;
}) {
  const { register, handleSubmit, formState } = useForm<DevolverForm>({
    resolver: zodResolver(devolverSchema),
    defaultValues: { id, motivo: "" },
  });
  const { errors, isSubmitting } = formState;

  return (
    <FormModal
      title="Devolver"
      confirmLabel="Devolver"
      onClose={onClose}
      enviando={isSubmitting}
      hayCambios={formState.isDirty}
      onSubmit={handleSubmit(async (d) => {
        const r = await devolverPedido(d);
        if (!r.success) {
          toast.error(r.error);
          return;
        }
        toast.success("Devuelta a borrador: a quien la pidió le llega el motivo");
        onClose();
      })}
    >
      <p className="t-body-m">
        Vuelve a borrador para que la corrijan, y lo demás que esperaba queda retirado.
      </p>
      <Campo id="devolver-motivo" label="Motivo" requerido error={errors.motivo}>
        <textarea
          id="devolver-motivo"
          rows={4}
          aria-required
          placeholder={ejemplo}
          className={claseInput(errors.motivo)}
          {...register("motivo")}
        />
      </Campo>
    </FormModal>
  );
}
