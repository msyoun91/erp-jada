"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Archive, Check, Copy, Pencil, Trash2, TriangleAlert, Undo2, X } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MOTIVO_PERDIDA } from "@/lib/entes";
import type { Database } from "@/lib/supabase/database.types";
import {
  aprobarPresupuesto,
  copiarVersion,
  desactivarPresupuesto,
  descartarVersion,
  guardarNombre,
  quitarVariante,
  rechazarPresupuesto,
  revertirPresupuesto,
} from "../actions";
import {
  aprobarSchema,
  nombreSchema,
  rechazarSchema,
  revertirSchema,
  type AprobarForm,
  type NombreForm,
  type RechazarForm,
  type RevertirForm,
} from "../types";

const NOMBRE_FORM = "presupuesto-nombre";

export function EditarNombre({ id, nombre }: { id: string; nombre: string }) {
  const [abierto, setAbierto] = useState(false);
  return (
    <>
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto(true)}>
        <Pencil size={14} />
        Editar
      </button>
      {abierto && <NombrePanel id={id} nombre={nombre} onClose={() => setAbierto(false)} />}
    </>
  );
}

function NombrePanel({ id, nombre, onClose }: { id: string; nombre: string; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<NombreForm>({
    resolver: zodResolver(nombreSchema),
    defaultValues: { id, nombre },
  });
  const { errors } = formState;

  async function onSubmit(data: NombreForm) {
    setEnviando(true);
    const result = await guardarNombre(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Nombre guardado");
    onClose();
  }

  return (
    <RightPanel
      title="Presupuesto"
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<PiePanel confirmar="Guardar" enviando={enviando} onCancelar={onClose} form={NOMBRE_FORM} />}
    >
      <form id={NOMBRE_FORM} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="pres-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="pres-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
          <p className="t-caption mt-1">Lo ve el cliente. Se puede cambiar hasta que se apruebe o se rechace.</p>
        </Campo>
      </form>
    </RightPanel>
  );
}

export type Aprobable = {
  id: string;
  numero: number;
  nombre: string;
  // "Vencida hace 3 días: los precios son del 1/10/26.": se aprueba igual (*Precio*).
  vencida: string | null;
};

// "La versión 3, sin publicar, se descarta." Aprobar y rechazar descartan lo abierto (*Estados y versiones*).
function textoAbiertas(abiertas: number[]) {
  if (abiertas.length === 0) return "";
  if (abiertas.length === 1) return ` La versión ${abiertas[0]}, sin publicar, se descarta.`;
  return ` Las versiones ${abiertas.slice(0, -1).join(", ")} y ${abiertas.at(-1)}, sin publicar, se descartan.`;
}

// Lo que se ofrece sale del estado y de quién mira (`arma`, `revierte`); la base frena igual (PR001, PR003, PR021–PR024, 42501).
export function AccionesPresupuesto({
  id,
  codigo,
  estado,
  aprobables,
  abiertas,
}: {
  id: string;
  codigo: string;
  estado: Database["public"]["Enums"]["estado_presupuesto"];
  aprobables: Aprobable[];
  // Números de las versiones en borrador o en revisión.
  abiertas: number[];
}) {
  const router = useRouter();
  const [dialogo, setDialogo] = useState<"aprobar" | "rechazar" | "revertir" | "desactivar" | null>(null);
  const cerrar = () => setDialogo(null);
  const items = [
    ...(estado === "aprobado" || estado === "rechazado" ? [{ label: "Revertir…", icon: <Undo2 size={14} />, onClick: () => setDialogo("revertir") }] : []),
    ...(estado === "borrador"
      ? [{ label: "Desactivar…", icon: <Archive size={14} />, onClick: () => setDialogo("desactivar"), destructive: true }]
      : []),
  ];

  return (
    <>
      {estado === "publicado" && (
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => setDialogo("rechazar")}>
            <X size={14} />
            Rechazar
          </button>
          <button type="button" className="btn btn-primary btn-sm" onClick={() => setDialogo("aprobar")}>
            <Check size={14} />
            Aprobar
          </button>
        </>
      )}
      {items.length > 0 && <OverflowMenu items={items} />}
      {dialogo === "aprobar" && <AprobarModal codigo={codigo} aprobables={aprobables} abiertas={abiertas} onClose={cerrar} />}
      {dialogo === "rechazar" && <RechazarModal id={id} codigo={codigo} abiertas={abiertas} onClose={cerrar} />}
      {dialogo === "revertir" && (estado === "aprobado" || estado === "rechazado") && (
        <RevertirModal id={id} codigo={codigo} estado={estado} onClose={cerrar} />
      )}
      {dialogo === "desactivar" && (
        <ConfirmModal
          title={`Desactivar ${codigo}`}
          mensaje="Sale de la lista y no vuelve. Nunca se publicó, así que la obra no cambia."
          onConfirm={async () => {
            const r = await desactivarPresupuesto(id);
            if (!r.success) {
              toast.error(r.error);
              return;
            }
            toast.success(`${codigo} desactivado`);
            router.push("/presupuestos");
          }}
          onClose={cerrar}
        />
      )}
    </>
  );
}

function AprobarModal({
  codigo,
  aprobables,
  abiertas,
  onClose,
}: {
  codigo: string;
  aprobables: Aprobable[];
  abiertas: number[];
  onClose: () => void;
}) {
  const varias = aprobables.length > 1;
  const { register, handleSubmit, control, formState } = useForm<AprobarForm>({
    resolver: zodResolver(aprobarSchema),
    defaultValues: { version: varias ? "" : aprobables[0]?.id },
  });
  const { errors, isSubmitting } = formState;
  const version = useWatch({ control, name: "version" });
  const elegida = aprobables.find((v) => v.id === version);

  return (
    <FormModal
      title={`Aprobar ${codigo}`}
      confirmLabel="Aprobar"
      onClose={onClose}
      enviando={isSubmitting}
      onSubmit={handleSubmit(async (d) => {
        const r = await aprobarPresupuesto(d);
        if (!r.success) {
          toast.error(r.error);
          return;
        }
        toast.success(`${codigo} aprobado`);
        onClose();
      })}
    >
      {varias ? (
        <fieldset>
          <legend className="t-label t-label-req mb-2">Variante que eligió el cliente</legend>
          <div className="flex flex-col gap-2">
            {aprobables.map((v) => (
              <label key={v.id} className="t-body-m flex items-center gap-2">
                <input type="radio" value={v.id} {...register("version")} />
                {v.nombre}
                <span className="t-caption">· versión {v.numero}</span>
              </label>
            ))}
          </div>
          {errors.version && <p className="input-error-text">{errors.version.message}</p>}
        </fieldset>
      ) : (
        aprobables[0] && (
          <p className="t-body-m">
            El cliente eligió <span className="font-semibold">{aprobables[0].nombre}</span>, versión {aprobables[0].numero}.
          </p>
        )
      )}
      {elegida?.vencida && (
        <p className="alert alert-warning flex items-start gap-2">
          <TriangleAlert size={16} className="mt-0.5 shrink-0" />
          {elegida.vencida}
        </p>
      )}
      <p className="t-body-m">
        {varias ? "Las demás variantes quedan inhabilitadas. " : ""}La obra queda contratada.{textoAbiertas(abiertas)}
      </p>
    </FormModal>
  );
}

function RechazarModal({
  id,
  codigo,
  abiertas,
  onClose,
}: {
  id: string;
  codigo: string;
  abiertas: number[];
  onClose: () => void;
}) {
  const { register, handleSubmit, control, formState } = useForm<RechazarForm>({
    resolver: zodResolver(rechazarSchema),
    defaultValues: { id, detalle: "" },
  });
  const { errors, isSubmitting } = formState;
  const motivo = useWatch({ control, name: "motivo" });

  return (
    <FormModal
      title={`Rechazar ${codigo}`}
      confirmLabel="Rechazar"
      onClose={onClose}
      enviando={isSubmitting}
      hayCambios={formState.isDirty}
      onSubmit={handleSubmit(async (d) => {
        const r = await rechazarPresupuesto(d);
        if (!r.success) {
          toast.error(r.error);
          return;
        }
        toast.success(`${codigo} rechazado`);
        onClose();
      })}
    >
      <p className="t-body-m">
        El cliente no eligió ninguna variante. Si la obra no tiene otros presupuestos publicados ni aprobados, queda perdida con
        este motivo.{textoAbiertas(abiertas)}
      </p>
      <Campo id="rechazo-motivo" label="Motivo" requerido error={errors.motivo}>
        <select id="rechazo-motivo" aria-required className={claseInput(errors.motivo)} {...register("motivo")}>
          <option value="">¿Por qué no lo eligió?</option>
          {Object.entries(MOTIVO_PERDIDA).map(([valor, m]) => (
            <option key={valor} value={valor}>
              {m.label}
            </option>
          ))}
        </select>
      </Campo>
      <Campo id="rechazo-detalle" label="Detalle" requerido={motivo === "otro"} error={errors.detalle}>
        <textarea
          id="rechazo-detalle"
          rows={3}
          placeholder={motivo ? MOTIVO_PERDIDA[motivo]?.ejemplo : undefined}
          className={claseInput(errors.detalle)}
          {...register("detalle")}
        />
      </Campo>
    </FormModal>
  );
}

function RevertirModal({
  id,
  codigo,
  estado,
  onClose,
}: {
  id: string;
  codigo: string;
  estado: "aprobado" | "rechazado";
  onClose: () => void;
}) {
  const { register, handleSubmit, formState } = useForm<RevertirForm>({
    resolver: zodResolver(revertirSchema),
    defaultValues: { id, causa: "" },
  });
  const { errors, isSubmitting } = formState;
  const aprobado = estado === "aprobado";

  return (
    <FormModal
      title={aprobado ? "Revertir la aprobación" : "Revertir el rechazo"}
      confirmLabel="Revertir"
      onClose={onClose}
      enviando={isSubmitting}
      hayCambios={formState.isDirty}
      onSubmit={handleSubmit(async (d) => {
        const r = await revertirPresupuesto(d);
        if (!r.success) {
          toast.error(r.error);
          return;
        }
        toast.success(`${codigo} volvió a publicado`);
        onClose();
      })}
    >
      <p className="t-body-m">
        {aprobado
          ? `${codigo} vuelve a publicado, sin variante elegida. Si la obra no tiene otro aprobado, vuelve a cotización.`
          : `${codigo} vuelve a publicado. Si este rechazo dejó la obra perdida, vuelve a cotización.`}{" "}
        Las versiones que se descartaron al {aprobado ? "aprobar" : "rechazar"} no vuelven.
      </p>
      <Campo id="revertir-causa" label="Por qué se revierte" requerido error={errors.causa}>
        <textarea
          id="revertir-causa"
          rows={3}
          aria-required
          placeholder={aprobado ? "Ej: se aprobó Aluminio y el cliente eligió PVC" : "Ej: se registró en el presupuesto equivocado"}
          className={claseInput(errors.causa)}
          {...register("causa")}
        />
      </Campo>
    </FormModal>
  );
}

type Abierta = { id: string; numero: number };

// Lo que se ofrece lo calcula la ficha; la base frena igual (PR003, PR005, PR006, PR015, PR016, 23505).
export function AccionesVariante({
  presupuestoId,
  nombre,
  publicada,
  abierta,
  quitable,
  descartable,
}: {
  presupuestoId: string;
  nombre: string;
  publicada: string | null;
  abierta: Abierta | null;
  // Hay otra variante publicada y el presupuesto está publicado.
  quitable: boolean;
  // La abierta es un borrador y no es la única versión activa del presupuesto.
  descartable: boolean;
}) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [confirmar, setConfirmar] = useState<"quitar" | "descartar" | null>(null);
  const cerrar = () => setConfirmar(null);
  // Sumar variante parte de la publicada, lo que vio el cliente: mantener en la nueva deja esos precios (*Pantallas*).
  const origen = publicada ?? abierta?.id ?? null;

  async function copiar(desde: string, nueva: boolean) {
    setEnviando(true);
    const result = await copiarVersion(desde, nueva);
    if (!result.success) {
      setEnviando(false);
      toast.error(result.error);
      return;
    }
    router.push(`/presupuestos/${presupuestoId}/${result.id}`);
  }

  function avisar(result: { success: true } | { success: false; error: string }, ok: string) {
    if (result.success) toast.success(ok);
    else toast.error(result.error);
  }

  const items = [
    ...(origen ? [{ label: "Sumar variante a partir de esta", icon: <Copy size={14} />, onClick: () => copiar(origen, true) }] : []),
    ...(publicada && quitable
      ? [{ label: "Quitar variante…", icon: <Archive size={14} />, onClick: () => setConfirmar("quitar"), destructive: true }]
      : []),
    ...(abierta && descartable
      ? [{ label: `Descartar la versión ${abierta.numero}…`, icon: <Trash2 size={14} />, onClick: () => setConfirmar("descartar"), destructive: true }]
      : []),
  ];

  return (
    <>
      {publicada && !abierta && (
        <button type="button" className="btn btn-secondary btn-sm" disabled={enviando} onClick={() => copiar(publicada, false)}>
          <Pencil size={14} />
          Corregir
        </button>
      )}
      {items.length > 0 && <OverflowMenu items={items} />}
      {confirmar === "quitar" && publicada && (
        <ConfirmModal
          title="Quitar variante"
          mensaje={`${nombre} deja de ofrecerse al cliente y el presupuesto sigue con las demás variantes.${
            abierta ? ` La versión ${abierta.numero} sigue abierta: si se publica, la variante vuelve.` : ""
          }`}
          confirmLabel="Quitar"
          onConfirm={async () => avisar(await quitarVariante(publicada), "Variante quitada")}
          onClose={cerrar}
        />
      )}
      {confirmar === "descartar" && abierta && (
        <ConfirmModal
          title={`Descartar la versión ${abierta.numero}`}
          mensaje={
            publicada
              ? "Se pierde lo que se cambió en el borrador. El cliente sigue viendo la publicada."
              : "Se pierde el borrador, con todo lo que tiene cargado."
          }
          confirmLabel="Descartar"
          onConfirm={async () => avisar(await descartarVersion(abierta.id), "Borrador descartado")}
          onClose={cerrar}
        />
      )}
    </>
  );
}
