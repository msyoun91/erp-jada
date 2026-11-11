"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MONEDAS, MONEDAS_LISTA } from "@/lib/monedas";
import { crearPresupuesto } from "../actions";
import { ALICUOTAS, altaSchema, formatAlicuota, type AltaForm } from "../types";

const FORM_ID = "presupuesto-alta-form";

export function AltaPresupuestoPanel({ obras, onClose }: { obras: { id: string; nombre: string }[]; onClose: () => void }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<AltaForm>({
    resolver: zodResolver(altaSchema),
    defaultValues: { obra: "", nombre: "", moneda: "ARS", alicuota: 21, seccion: "" },
  });
  const { errors } = formState;

  async function onSubmit(data: AltaForm) {
    setEnviando(true);
    const result = await crearPresupuesto(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Presupuesto creado");
    router.push(`/presupuestos/${result.id}`);
    onClose();
  }

  return (
    <RightPanel
      title="Nuevo presupuesto"
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<PiePanel confirmar="Crear presupuesto" enviando={enviando} onCancelar={onClose} form={FORM_ID} />}
    >
      <form id={FORM_ID} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="pres-obra" label="Obra" requerido error={errors.obra}>
          <select id="pres-obra" aria-required className={claseInput(errors.obra)} {...register("obra")}>
            <option value="">Elegí la obra</option>
            {obras.map((o) => (
              <option key={o.id} value={o.id}>
                {o.nombre}
              </option>
            ))}
          </select>
        </Campo>
        <Campo id="pres-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="pres-nombre" aria-required placeholder="Ej: Aberturas planta baja" className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo id="pres-moneda" label="Moneda de la primera sección" requerido error={errors.moneda}>
          <select id="pres-moneda" aria-required className={claseInput(errors.moneda)} {...register("moneda")}>
            {MONEDAS_LISTA.map((m) => (
              <option key={m} value={m}>
                {MONEDAS[m]}
              </option>
            ))}
          </select>
        </Campo>
        <Campo id="pres-alicuota" label="IVA de la primera sección" requerido error={errors.alicuota}>
          <select id="pres-alicuota" aria-required className={claseInput(errors.alicuota)} {...register("alicuota")}>
            {ALICUOTAS.map((a) => (
              <option key={a} value={a}>
                {formatAlicuota(a)}
              </option>
            ))}
          </select>
        </Campo>
        <Campo id="pres-seccion" label="Nombre de la sección" error={errors.seccion}>
          <input id="pres-seccion" placeholder="General" className={claseInput(errors.seccion)} {...register("seccion")} />
        </Campo>
      </form>
    </RightPanel>
  );
}
