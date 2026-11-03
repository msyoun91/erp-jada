"use client";

import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearInsumo, editarInsumo } from "../actions";
import { POR_UNIDAD, UNIDAD } from "../etiquetas";
import { UNIDADES, insumoSchema, type Categoria, type Color, type Insumo, type InsumoForm } from "../types";

const numeroONulo = (v: unknown) => (v === "" || v === null ? null : Number(v));

// Alta y edición. Después de enviarse una versión que lo usa, la base deja cambiar solo un peso o
// espesor vacío (CA006): el formulario no lo adivina, porque Técnica no siempre ve los paquetes.
export function InsumoFormPanel({
  insumo,
  categorias,
  colores,
  onClose,
}: {
  insumo: Insumo | null;
  categorias: Categoria[];
  colores: Color[];
  onClose: () => void;
}) {
  const { register, handleSubmit, control, formState } = useForm<InsumoForm>({
    resolver: zodResolver(insumoSchema),
    defaultValues: insumo
      ? {
          nombre: insumo.nombre,
          categoria_id: insumo.categoria_id,
          unidad: insumo.unidad,
          peso: insumo.peso,
          espesor: insumo.espesor,
          colores: [],
          con_color: insumo.con_color,
        }
      : { nombre: "", categoria_id: "", unidad: "mm", peso: null, espesor: null, colores: [], con_color: false },
  });
  const { errors, isSubmitting } = formState;
  const unidad = useWatch({ control, name: "unidad" });
  const elegibles = categorias.filter((c) => c.activo || c.id === insumo?.categoria_id);

  async function guardar(datos: InsumoForm) {
    const r = insumo ? await editarInsumo({ ...datos, id: insumo.id }) : await crearInsumo(datos);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(insumo ? "Insumo guardado" : `Se cargó ${datos.nombre}. A quienes cargan costos les llega un aviso.`);
    onClose();
  }

  return (
    <RightPanel
      title={insumo ? `Editar ${insumo.nombre}` : "Nuevo insumo"}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <button className="btn btn-primary" onClick={handleSubmit(guardar)} disabled={isSubmitting}>
          {isSubmitting ? "Guardando…" : "Guardar"}
        </button>
      }
    >
      <form onSubmit={handleSubmit(guardar)} className="flex flex-col gap-4 overflow-y-auto p-5">
        <Campo id="insumo-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="insumo-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo id="insumo-categoria" label="Categoría" requerido error={errors.categoria_id}>
          <select
            id="insumo-categoria"
            aria-required
            className={claseInput(errors.categoria_id)}
            {...register("categoria_id")}
          >
            <option value="">Elegí una</option>
            {elegibles.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre}
                {c.activo ? "" : " (de baja)"}
              </option>
            ))}
          </select>
        </Campo>
        <Campo id="insumo-unidad" label="Unidad" requerido error={errors.unidad}>
          <select id="insumo-unidad" aria-required className={claseInput(errors.unidad)} {...register("unidad")}>
            {UNIDADES.map((u) => (
              <option key={u} value={u}>
                {UNIDAD[u]}
              </option>
            ))}
          </select>
        </Campo>
        <div className="grid grid-cols-2 gap-3">
          <Campo id="insumo-peso" label={`Peso (kg/${POR_UNIDAD[unidad]})`} error={errors.peso}>
            <input
              id="insumo-peso"
              type="number"
              step="any"
              min="0"
              inputMode="decimal"
              className={claseInput(errors.peso)}
              {...register("peso", { setValueAs: numeroONulo })}
            />
          </Campo>
          <Campo id="insumo-espesor" label="Espesor (mm)" error={errors.espesor}>
            <input
              id="insumo-espesor"
              type="number"
              step="any"
              min="0"
              inputMode="decimal"
              className={claseInput(errors.espesor)}
              {...register("espesor", { setValueAs: numeroONulo })}
            />
          </Campo>
        </div>
        <p className="t-caption">
          Vacío no es 0: si una pieza cuenta este dato, la versión no se puede enviar hasta completarlo. Se completa una
          vez, aunque ya se use.
        </p>

        {insumo ? (
          <label className="tap-target flex items-start gap-2">
            <input type="checkbox" className="mt-1" {...register("con_color")} />
            <span className="t-body-m">
              Tiene colores
              <span className="t-caption block">
                Pasar a colores apaga la variante indistinta; volver a indistinto apaga los colores. Queda fijo cuando se
                envía una versión que lo usa.
              </span>
            </span>
          </label>
        ) : (
          <fieldset className="flex flex-col gap-1">
            <legend className="t-label mb-1">Colores</legend>
            <p className="t-caption mb-1">Sin ninguno, es de color indistinto: una sola variante.</p>
            {colores
              .filter((c) => c.activo)
              .map((c) => (
                <label key={c.id} className="tap-target flex items-center gap-2">
                  <input type="checkbox" value={c.id} {...register("colores")} />
                  <span className="t-body-m">{c.nombre}</span>
                </label>
              ))}
          </fieldset>
        )}
      </form>
    </RightPanel>
  );
}
