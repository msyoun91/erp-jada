"use client";

import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarOpcion } from "../../actions";
import { EJEMPLO } from "../../ejemplos";
import { opcionSchema, type Condicion, type Opcion, type OpcionForm } from "../../types";
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
  insumos: InsumosPorId;
  condiciones: Condicion[];
  nombres: string[];
  onClose: () => void;
}) {
  const { register, handleSubmit, formState } = useForm<OpcionForm>({
    resolver: zodResolver(opcionSchema),
    defaultValues: opcion
      ? { ...opcion, version_id: versionId }
      : { id: null, version_id: versionId, material_id: materialId, orden, insumo_id: "", predeterminada: false },
  });
  const { errors, isSubmitting } = formState;

  async function guardar(d: OpcionForm) {
    const r = await guardarOpcion(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success("Opción guardada");
    onClose();
  }

  const formulas = [
    { campo: "medida", label: "Medida (mm), para insumos en mm o u", ejemplo: EJEMPLO.opcionMedida },
    { campo: "ancho", label: "Ancho (mm), para insumos en m2", ejemplo: EJEMPLO.anchoAlto },
    { campo: "alto", label: "Alto (mm), para insumos en m2", ejemplo: EJEMPLO.anchoAlto },
    { campo: "area", label: "Área (mm²), solo si no es un rectángulo", ejemplo: EJEMPLO.area },
    { campo: "cantidad", label: "Cantidad", ejemplo: EJEMPLO.opcionCantidad },
  ] as const;

  return (
    <RightPanel
      title={opcion ? `Opción ${insumos.get(opcion.insumo_id ?? "")?.nombre ?? ""}` : "Nueva opción"}
      subtitle="Vacío: lo hereda del material."
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
          <Campo id="opcion-insumo" label="Insumo o servicio fijo" requerido error={errors.insumo_id}>
            <InsumoSelect
              id="opcion-insumo"
              insumos={insumos}
              actual={opcion?.insumo_id}
              registro={register("insumo_id")}
            />
          </Campo>
          {conPredeterminada && (
            <label className="tap-target flex items-center gap-2">
              <input type="checkbox" {...register("predeterminada")} />
              <span className="t-body-m">Predeterminada</span>
            </label>
          )}
          {formulas.map(({ campo, label, ejemplo }) => (
            <Campo key={campo} id={`opcion-${campo}`} label={label} error={errors[campo]} ejemplo={ejemplo}>
              <input id={`opcion-${campo}`} className={`${claseInput(errors[campo])} font-mono`} {...register(campo)} />
            </Campo>
          ))}
          <Nombres nombres={nombres} />
        </form>
        {opcion && <CondicionesLista versionId={versionId} de={{ opcion_id: opcion.id }} condiciones={condiciones} />}
      </div>
    </RightPanel>
  );
}
