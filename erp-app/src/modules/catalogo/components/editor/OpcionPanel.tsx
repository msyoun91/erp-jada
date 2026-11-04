"use client";

import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarOpcion } from "../../actions";
import { opcionSchema, type Condicion, type Opcion, type OpcionForm } from "../../types";
import { CamposMedida } from "./CamposMedida";
import { CondicionesLista } from "./CondicionesLista";
import { InsumoSelect, type InsumosPorId } from "./InsumoSelect";
import { Nombres } from "./Nombres";

// Lo que la opción no trae lo hereda del material, cada dato por separado; la medida, solo con la misma unidad.
export function OpcionPanel({
  versionId,
  materialId,
  opcion,
  orden,
  conPredeterminada,
  parejaDe,
  insumos,
  condiciones,
  nombres,
  onClose,
}: {
  versionId: string;
  materialId: string;
  opcion: Opcion | null;
  orden: number;
  conPredeterminada: boolean;
  // Una pareja elige su insumo en la lista de parejas; dos pueden ser el mismo, y esto dice de cuál se trata.
  parejaDe?: string;
  insumos: InsumosPorId;
  condiciones: Condicion[];
  nombres: string[];
  onClose: () => void;
}) {
  const { register, handleSubmit, formState, control, getValues } = useForm<OpcionForm>({
    resolver: zodResolver(opcionSchema),
    defaultValues: opcion
      ? { ...opcion, version_id: versionId }
      : { id: null, version_id: versionId, material_id: materialId, orden, insumo_id: "", predeterminada: false },
  });
  const { errors, isSubmitting } = formState;
  const insumo = insumos.get(useWatch({ control, name: "insumo_id" }) ?? "");

  async function guardar(d: OpcionForm) {
    const r = await guardarOpcion(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success("Opción guardada");
    onClose();
  }

  return (
    <RightPanel
      title={opcion ? `Opción ${insumos.get(opcion.insumo_id ?? "")?.nombre ?? ""}` : "Nueva opción"}
      subtitle={`${parejaDe ? `Con ${parejaDe}. ` : ""}Vacío: lo hereda del material.`}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <button className="btn btn-primary" onClick={handleSubmit(guardar)} disabled={isSubmitting}>
          Guardar
        </button>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto p-5">
        <form onSubmit={handleSubmit(guardar)} className="flex flex-col gap-4">
          {!parejaDe && (
            <Campo id="opcion-insumo" label="Insumo o servicio fijo" requerido error={errors.insumo_id}>
              <InsumoSelect
                id="opcion-insumo"
                insumos={insumos}
                actual={opcion?.insumo_id}
                registro={register("insumo_id")}
              />
            </Campo>
          )}
          {conPredeterminada && (
            <label className="tap-target flex items-center gap-2">
              <input type="checkbox" {...register("predeterminada")} />
              <span className="t-body-m">Predeterminada</span>
            </label>
          )}
          <CamposMedida
            usados={insumo ? [insumo] : []}
            conValor={(c) => Boolean(opcion?.[c] || getValues(c))}
            campo={(c, label) => (
              <Campo id={`opcion-${c}`} label={label} error={errors[c]}>
                <input id={`opcion-${c}`} className={`${claseInput(errors[c])} font-mono`} {...register(c)} />
              </Campo>
            )}
          />
          <Campo id="opcion-cantidad" label="Cantidad" error={errors.cantidad}>
            <input id="opcion-cantidad" className={`${claseInput(errors.cantidad)} font-mono`} {...register("cantidad")} />
          </Campo>
          <Nombres nombres={nombres} />
        </form>
        {opcion && <CondicionesLista versionId={versionId} de={{ opcion_id: opcion.id }} condiciones={condiciones} />}
      </div>
    </RightPanel>
  );
}
