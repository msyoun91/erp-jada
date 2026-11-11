"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Archive, Copy, Pencil, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { copiarVersion, descartarVersion, guardarNombre, quitarVariante } from "../actions";
import { nombreSchema, type NombreForm } from "../types";

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
