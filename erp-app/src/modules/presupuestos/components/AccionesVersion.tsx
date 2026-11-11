"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Layers, Pencil } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MONEDAS, MONEDAS_LISTA } from "@/lib/monedas";
import { cambiarTodasLasSecciones, guardarDatosVersion } from "../actions";
import type { VersionEditor } from "../queries";
import {
  ALICUOTAS,
  datosVersionSchema,
  formatAlicuota,
  todasSeccionesSchema,
  type DatosVersionForm,
  type TodasSeccionesForm,
} from "../types";

type Version = VersionEditor["version"];

export function AccionesVersion({ version, tope, variasSecciones }: { version: Version; tope: number | null; variasSecciones: boolean }) {
  const [abierto, setAbierto] = useState<"datos" | "secciones" | null>(null);
  const cerrar = () => setAbierto(null);
  return (
    <>
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto("datos")}>
        <Pencil size={14} />
        Editar
      </button>
      {variasSecciones && (
        <OverflowMenu items={[{ label: "Todas las secciones…", icon: <Layers size={14} />, onClick: () => setAbierto("secciones") }]} />
      )}
      {abierto === "datos" && <DatosVersionPanel version={version} tope={tope} onClose={cerrar} />}
      {abierto === "secciones" && <TodasSeccionesPanel versionId={version.id} onClose={cerrar} />}
    </>
  );
}

const DATOS_FORM = "presupuesto-version-datos";

function DatosVersionPanel({ version: v, tope, onClose }: { version: Version; tope: number | null; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<DatosVersionForm>({
    resolver: zodResolver(datosVersionSchema),
    defaultValues: { id: v.id, variante_nombre: v.variante_nombre ?? "", iva_discriminado: v.iva_discriminado, descuento: v.descuento },
  });
  const { errors } = formState;

  async function onSubmit(data: DatosVersionForm) {
    setEnviando(true);
    const result = await guardarDatosVersion(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Versión guardada");
    onClose();
  }

  return (
    <RightPanel
      title={`Versión ${v.numero}`}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<PiePanel confirmar="Guardar" enviando={enviando} onCancelar={onClose} form={DATOS_FORM} />}
    >
      <form id={DATOS_FORM} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="ver-variante" label="Nombre de la variante" error={errors.variante_nombre}>
          <input id="ver-variante" placeholder="Ej: Aluminio" className={claseInput(errors.variante_nombre)} {...register("variante_nombre")} />
          <p className="t-caption mt-1">Lo ve el cliente. Hace falta si el presupuesto tiene otra variante publicada.</p>
        </Campo>
        <Campo id="ver-iva" label="IVA" requerido error={errors.iva_discriminado}>
          <select
            id="ver-iva"
            aria-required
            className={claseInput(errors.iva_discriminado)}
            {...register("iva_discriminado", { setValueAs: (x: unknown) => x === true || x === "true" })}
          >
            <option value="true">Discriminado</option>
            <option value="false">Incluido en cada precio</option>
          </select>
        </Campo>
        <Campo id="ver-descuento" label="Descuento (%)" error={errors.descuento}>
          <input
            id="ver-descuento"
            type="number"
            step="any"
            min="0"
            max="100"
            inputMode="decimal"
            className={claseInput(errors.descuento)}
            {...register("descuento")}
          />
          <p className="t-caption mt-1">
            {tope === null
              ? "Gerencia todavía no configuró el tope: cualquier descuento pide autorización."
              : `Hasta ${formatAlicuota(tope)} no pide autorización.`}
          </p>
        </Campo>
      </form>
    </RightPanel>
  );
}

const SECCIONES_FORM = "presupuesto-todas-secciones";

function TodasSeccionesPanel({ versionId, onClose }: { versionId: string; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<TodasSeccionesForm>({
    resolver: zodResolver(todasSeccionesSchema),
    defaultValues: { version_id: versionId, moneda: "", alicuota: "" },
  });
  const { errors } = formState;

  async function onSubmit(data: TodasSeccionesForm) {
    setEnviando(true);
    const result = await cambiarTodasLasSecciones(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Secciones cambiadas");
    onClose();
  }

  return (
    <RightPanel
      title="Todas las secciones"
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <PiePanel
          confirmar="Cambiar todas"
          enviando={enviando}
          onCancelar={onClose}
          form={SECCIONES_FORM}
          nota="Con otra moneda, las ventanas se recalculan."
        />
      }
    >
      <form id={SECCIONES_FORM} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="todas-moneda" label="Moneda" error={errors.moneda}>
          <select id="todas-moneda" className={claseInput(errors.moneda)} {...register("moneda")}>
            <option value="">Como está cada una</option>
            {MONEDAS_LISTA.map((m) => (
              <option key={m} value={m}>
                {MONEDAS[m]}
              </option>
            ))}
          </select>
        </Campo>
        <Campo id="todas-alicuota" label="IVA" error={errors.alicuota}>
          <select id="todas-alicuota" className={claseInput(errors.alicuota)} {...register("alicuota")}>
            <option value="">Como está cada una</option>
            {ALICUOTAS.map((a) => (
              <option key={a} value={a}>
                {formatAlicuota(a)}
              </option>
            ))}
          </select>
        </Campo>
      </form>
    </RightPanel>
  );
}
