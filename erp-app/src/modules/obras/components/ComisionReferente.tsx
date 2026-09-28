"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { CircleDollarSign, Plus } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { formatFecha } from "@/lib/utils";
import { registrarComision } from "../actions";
import { textoComision } from "../etiquetas";
import { comisionSchema, type Comision, type ComisionForm } from "../types";

// La comisión de un referente, en su fila de la sección Contactos (la compone
// `app/`). Solo llega a quien tiene la obra a cargo: la RLS no le da filas a
// nadie más. Cambiarla crea otra; las inactivas son el "Antes".
export function ComisionReferente({
  vinculoId,
  comisiones,
  abierto,
  yo,
  nombres,
}: {
  vinculoId: string;
  comisiones: Comision[];
  abierto: boolean;
  yo: string;
  nombres: Record<string, string>;
}) {
  const [cargando, setCargando] = useState(false);
  const vigente = comisiones.find((c) => c.activo) ?? null;
  const anteriores = comisiones.filter((c) => !c.activo);

  return (
    <div className="t-caption mt-1 flex flex-col gap-0.5">
      {vigente ? (
        <p className="flex flex-wrap items-center gap-x-2">
          <CircleDollarSign size={12} strokeWidth={1.75} className="shrink-0" />
          <span className="font-medium text-text-primary">Comisión {textoComision(vigente)}</span>
          {abierto && (
            <button className="text-text-brand hover:underline" onClick={() => setCargando(true)}>
              Cambiar
            </button>
          )}
        </p>
      ) : (
        abierto && (
          <button className="flex items-center gap-1 self-start text-text-brand hover:underline" onClick={() => setCargando(true)}>
            <Plus size={12} />
            Cargar comisión
          </button>
        )
      )}
      {anteriores.map((c) => (
        <p key={c.id} className="text-text-tertiary">
          Antes: {textoComision(c)} — {c.creado_por === yo ? "Vos" : (nombres[c.creado_por] ?? "—")}, {formatFecha(c.created_at)}
        </p>
      ))}
      {cargando && <ComisionModal vinculoId={vinculoId} vigente={vigente} onClose={() => setCargando(false)} />}
    </div>
  );
}

function ComisionModal({ vinculoId, vigente, onClose }: { vinculoId: string; vigente: Comision | null; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, control, formState } = useForm<ComisionForm>({
    resolver: zodResolver(comisionSchema),
    defaultValues: {
      vinculo_id: vinculoId,
      tipo: vigente?.monto != null ? "monto" : "porcentaje",
      valor: vigente?.porcentaje ?? vigente?.monto ?? undefined,
      moneda: vigente?.moneda ?? "USD",
    },
  });
  const { errors } = formState;
  const tipo = useWatch({ control, name: "tipo" });

  async function onSubmit(data: ComisionForm) {
    setEnviando(true);
    const result = await registrarComision(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(vigente ? "Comisión cambiada" : "Comisión cargada");
    onClose();
  }

  return (
    <FormModal
      title={vigente ? "Cambiar comisión" : "Cargar comisión"}
      confirmLabel="Guardar"
      onClose={onClose}
      onSubmit={handleSubmit(onSubmit)}
      enviando={enviando}
      hayCambios={formState.isDirty}
    >
      {vigente && (
        <p className="t-body-m">
          Hoy es <span className="font-semibold">{textoComision(vigente)}</span>. La nueva la reemplaza y esta queda como
          «Antes».
        </p>
      )}
      <fieldset className="flex gap-4">
        <legend className="t-label mb-1">Se pacta como</legend>
        <label className="t-body-m flex items-center gap-2">
          <input type="radio" value="porcentaje" {...register("tipo")} />
          Porcentaje de lo contratado
        </label>
        <label className="t-body-m flex items-center gap-2">
          <input type="radio" value="monto" {...register("tipo")} />
          Monto fijo
        </label>
      </fieldset>
      <div className="flex gap-3">
        {tipo === "monto" && (
          <Campo id="comision-moneda" label="Moneda" requerido>
            <select id="comision-moneda" className={claseInput()} {...register("moneda")}>
              <option value="USD">USD</option>
              <option value="ARS">ARS</option>
            </select>
          </Campo>
        )}
        <div className="flex-1">
          <Campo id="comision-valor" label={tipo === "monto" ? "Monto" : "Porcentaje"} requerido error={errors.valor}>
            <input
              id="comision-valor"
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              aria-required
              className={claseInput(errors.valor)}
              {...register("valor", { valueAsNumber: true })}
            />
          </Campo>
        </div>
      </div>
    </FormModal>
  );
}
