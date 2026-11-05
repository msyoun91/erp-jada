"use client";

import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MONEDAS, MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import { crearFijo, editarFijo } from "../actions";
import { POR_UNIDAD, UNIDAD } from "../etiquetas";
import { UNIDADES, fijoSchema, type Categoria, type FijoForm, type Insumo } from "../types";

const numeroONulo = (v: unknown) => (v === "" || v === null ? null : Number(v));

// El servicio fijo nace con su costo: sin costo no nace. En la edición, el costo va por "Cargar costo".
export function FijoFormPanel({
  fijo,
  categorias,
  monedaPrincipal,
  onClose,
}: {
  fijo: Insumo | null;
  categorias: Categoria[];
  monedaPrincipal: Moneda;
  onClose: () => void;
}) {
  // En la edición el costo no se manda: un valor cualquiera pasa la validación del formulario.
  const { register, handleSubmit, control, formState } = useForm<FijoForm>({
    resolver: zodResolver(fijoSchema),
    defaultValues: fijo
      ? { nombre: fijo.nombre, categoria_id: fijo.categoria_id, unidad: fijo.unidad, costo: 1, moneda: monedaPrincipal }
      : { nombre: "", categoria_id: "", unidad: "u", costo: undefined, moneda: monedaPrincipal },
  });
  const { errors, isSubmitting } = formState;
  const unidad = useWatch({ control, name: "unidad" });
  const elegibles = categorias.filter((c) => c.activo || c.id === fijo?.categoria_id);

  async function guardar(d: FijoForm) {
    const r = fijo
      ? await editarFijo({ id: fijo.id, nombre: d.nombre, categoria_id: d.categoria_id, unidad: d.unidad })
      : await crearFijo(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(fijo ? "Servicio guardado" : `Se cargó ${d.nombre}`);
    onClose();
  }

  return (
    <RightPanel
      title={fijo ? `Editar ${fijo.nombre}` : "Nuevo servicio fijo"}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<PiePanel confirmar="Guardar" enviando={isSubmitting} onCancelar={onClose} onConfirmar={handleSubmit(guardar)} />}
    >
      <form onSubmit={handleSubmit(guardar)} className="flex flex-col gap-4 overflow-y-auto p-5">
        <Campo id="fijo-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="fijo-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo id="fijo-categoria" label="Categoría" requerido error={errors.categoria_id}>
          <select
            id="fijo-categoria"
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
        <Campo id="fijo-unidad" label="Unidad" requerido error={errors.unidad}>
          <select id="fijo-unidad" aria-required className={claseInput(errors.unidad)} {...register("unidad")}>
            {UNIDADES.map((u) => (
              <option key={u} value={u}>
                {UNIDAD[u]}
              </option>
            ))}
          </select>
        </Campo>
        {!fijo && (
          <div className="flex gap-2">
            <div className="flex-1">
              <Campo
                id="fijo-costo"
                label={`Costo (por ${POR_UNIDAD[unidad]}, sin IVA)`}
                requerido
                error={errors.costo}
              >
                <input
                  id="fijo-costo"
                  type="number"
                  step="any"
                  min="0"
                  inputMode="decimal"
                  aria-required
                  className={claseInput(errors.costo)}
                  {...register("costo", { setValueAs: numeroONulo })}
                />
              </Campo>
            </div>
            <Campo id="fijo-moneda" label="Moneda" requerido error={errors.moneda}>
              <select id="fijo-moneda" aria-required className="input w-auto" {...register("moneda")}>
                {MONEDAS_LISTA.map((m) => (
                  <option key={m} value={m}>
                    {MONEDAS[m]}
                  </option>
                ))}
              </select>
            </Campo>
          </div>
        )}
      </form>
    </RightPanel>
  );
}
