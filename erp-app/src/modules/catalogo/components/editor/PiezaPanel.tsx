"use client";

import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Ayuda } from "@/components/ui/Ayuda";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarPieza } from "../../actions";
import { EJEMPLO } from "../../ejemplos";
import { piezaSchema, type Pieza, type PiezaForm } from "../../types";
import { Nombres } from "./Nombres";

export function PiezaPanel({
  versionId,
  pieza,
  piezas,
  nombres,
  onClose,
}: {
  versionId: string;
  pieza: Pieza | null;
  piezas: Pieza[];
  nombres: string[];
  onClose: () => void;
}) {
  const { register, handleSubmit, control, formState } = useForm<PiezaForm>({
    resolver: zodResolver(piezaSchema),
    defaultValues: pieza
      ? { ...pieza, version_id: versionId }
      : { id: null, version_id: versionId, orden: piezas.length, nombre: "", cantidad: "1" },
  });
  const { errors, isSubmitting } = formState;
  const opcional = useWatch({ control, name: "opcional" });
  const otras = piezas.filter((p) => p.opcional && p.id !== pieza?.id);

  async function guardar(d: PiezaForm) {
    const r = await guardarPieza(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(pieza ? "Pieza guardada" : `Se sumó ${d.nombre}`);
    onClose();
  }

  return (
    <RightPanel
      title={pieza ? `Pieza ${pieza.nombre}` : "Nueva pieza armada"}
      subtitle="Lo de adentro es para una sola pieza; la cantidad lo multiplica."
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <button className="btn btn-primary" onClick={handleSubmit(guardar)} disabled={isSubmitting}>
          Guardar
        </button>
      }
    >
      <form onSubmit={handleSubmit(guardar)} className="flex flex-col gap-4 overflow-y-auto p-5">
        <Campo id="pieza-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="pieza-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo
          id="pieza-cantidad"
          label="Cantidad (fórmula; vacía es 1)"
          error={errors.cantidad}
          ejemplo={EJEMPLO.piezaCantidad}
        >
          <input id="pieza-cantidad" className={`${claseInput(errors.cantidad)} font-mono`} {...register("cantidad")} />
        </Campo>
        <Nombres nombres={nombres} />

        <Ayuda de="Opcional" ejemplo={EJEMPLO.opcional}>
          <label className="tap-target flex items-start gap-2">
            <input type="checkbox" className="mt-1" {...register("opcional")} />
            <span className="t-body-m">
              Opcional
              <span className="t-caption block">La suma o la saca el vendedor.</span>
            </span>
          </label>
        </Ayuda>
        {opcional && (
          <div className="flex flex-col gap-3 border-l-2 border-border pl-3">
            <label className="tap-target flex items-center gap-2">
              <input type="checkbox" {...register("incluida")} />
              <span className="t-body-m">Viene incluida</span>
            </label>
            <label className="tap-target flex items-center gap-2">
              <input type="checkbox" {...register("secundario")} />
              <span className="t-body-m">Secundaria: va plegada en &quot;Más opciones&quot;</span>
            </label>
            <Campo
              id="pieza-requiere"
              label="Requiere otra pieza opcional"
              error={errors.requiere_pieza_id}
              ejemplo={EJEMPLO.requiere}
            >
              <select id="pieza-requiere" className="input" {...register("requiere_pieza_id")}>
                <option value="">Ninguna</option>
                {otras.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.nombre}
                  </option>
                ))}
              </select>
            </Campo>
          </div>
        )}

        <Ayuda de="Calcula el espesor" ejemplo={EJEMPLO.calculaEspesor}>
          <label className="tap-target flex items-start gap-2">
            <input type="checkbox" className="mt-1" {...register("calcula_espesor")} />
            <span className="t-body-m">
              Calcula el espesor
              <span className="t-caption block">Suma el de los materiales marcados. El peso se calcula siempre.</span>
            </span>
          </label>
        </Ayuda>
        <fieldset className="flex flex-col gap-1">
          <legend className="t-label mb-1">Pasan a Producción</legend>
          <label className="tap-target flex items-center gap-2">
            <input type="checkbox" {...register("peso_a_produccion")} />
            <span className="t-body-m">El peso</span>
          </label>
          <label className="tap-target flex items-center gap-2">
            <input type="checkbox" {...register("espesor_a_produccion")} />
            <span className="t-body-m">El espesor</span>
          </label>
        </fieldset>
      </form>
    </RightPanel>
  );
}
