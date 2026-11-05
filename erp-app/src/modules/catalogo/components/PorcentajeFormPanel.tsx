"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { ConfirmModal } from "@/components/ui/Modal";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MONEDAS, MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import { guardarPorcentaje } from "../actions";
import { PASO } from "../etiquetas";
import { porcentajeSchema, type Categoria, type Porcentaje, type PorcentajeForm } from "../types";

const numeroONulo = (v: unknown) => (v === "" || v === null ? null : Number(v));

// Cada guardado es un valor nuevo con fecha y le avisa al gerente: sin cambios, la base no suma nada.
export function PorcentajeFormPanel({
  porcentaje,
  categoriasInsumo,
  categoriasServicio,
  monedaPrincipal,
  onClose,
}: {
  porcentaje: Porcentaje | null;
  categoriasInsumo: Categoria[];
  categoriasServicio: Categoria[];
  monedaPrincipal: Moneda;
  onClose: () => void;
}) {
  const router = useRouter();
  const [rojo, setRojo] = useState<PorcentajeForm | null>(null);
  const { register, handleSubmit, control, formState } = useForm<PorcentajeForm>({
    resolver: zodResolver(porcentajeSchema),
    defaultValues: porcentaje
      ? {
          ...porcentaje,
          minimo_moneda: porcentaje.minimo_moneda ?? monedaPrincipal,
          minimo_por: porcentaje.minimo_por ?? "paquete",
          confirmar_rojo: false,
        }
      : {
          id: null,
          nombre: "",
          porcentaje: undefined,
          paso: 1,
          categorias: [],
          minimo: null,
          minimo_moneda: monedaPrincipal,
          minimo_por: "paquete",
          opcional: false,
          confirmar_rojo: false,
        },
  });
  const { errors, isSubmitting } = formState;
  const paso = useWatch({ control, name: "paso" });

  async function guardar(datos: PorcentajeForm) {
    const r = await guardarPorcentaje(datos);
    if ("pideConfirmar" in r) {
      setRojo(datos);
      return;
    }
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(porcentaje ? "Cambio guardado. Al gerente le llega un aviso." : `Se cargó ${datos.nombre}`);
    onClose();
    if (!porcentaje) router.push(`/catalogo/porcentajes/${r.id}`);
  }

  const grupos = [
    { titulo: "De insumo", lista: categoriasInsumo },
    { titulo: "De servicio", lista: categoriasServicio },
  ];

  return (
    <>
      <RightPanel
        title={porcentaje ? `Cambiar ${porcentaje.nombre}` : "Nuevo servicio en %"}
        subtitle="Rige desde que se guarda. Cada cambio queda en la historia y se puede revertir."
        onClose={onClose}
        hayCambios={formState.isDirty}
        footer={<PiePanel confirmar="Guardar" enviando={isSubmitting} onCancelar={onClose} onConfirmar={handleSubmit(guardar)} />}
      >
        <form onSubmit={handleSubmit(guardar)} className="flex flex-col gap-4 overflow-y-auto p-5">
          <Campo id="pct-nombre" label="Nombre" requerido error={errors.nombre}>
            <input id="pct-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
          </Campo>
          <Campo id="pct-porcentaje" label="Porcentaje (%)" requerido error={errors.porcentaje}>
            <input
              id="pct-porcentaje"
              type="number"
              step="any"
              min="0"
              inputMode="decimal"
              aria-required
              className={claseInput(errors.porcentaje)}
              {...register("porcentaje", { setValueAs: numeroONulo })}
            />
          </Campo>
          <Campo id="pct-paso" label="Sobre qué se calcula" requerido error={errors.paso}>
            <select
              id="pct-paso"
              aria-required
              className={claseInput(errors.paso)}
              {...register("paso", { setValueAs: Number })}
            >
              {[1, 2, 3].map((n) => (
                <option key={n} value={n}>
                  {PASO[n].titulo}
                </option>
              ))}
            </select>
            <p className="t-caption mt-1">{PASO[paso]?.ayuda}</p>
          </Campo>

          {paso === 1 && (
            <fieldset className="flex flex-col gap-1">
              <legend className="t-label mb-1">Categorías</legend>
              <p className="t-caption mb-1">Sin ninguna, se cobra sobre todo el despiece.</p>
              {grupos.map((g) => (
                <div key={g.titulo} className="flex flex-col">
                  <p className="t-caption font-medium">{g.titulo}</p>
                  {g.lista.length === 0 && <p className="t-caption">Todavía no hay.</p>}
                  {g.lista.map((c) => (
                    <label key={c.id} className="tap-target flex items-center gap-2">
                      <input type="checkbox" value={c.id} {...register("categorias")} />
                      <span className={`t-body-m ${c.activo ? "" : "text-text-tertiary"}`}>
                        {c.nombre}
                        {c.activo ? "" : " (de baja: no cobra)"}
                      </span>
                    </label>
                  ))}
                </div>
              ))}
            </fieldset>
          )}

          {paso !== 3 && (
            <fieldset className="flex flex-col gap-2">
              <legend className="t-label mb-1">Mínimo</legend>
              <p className="t-caption">Vacío: sin mínimo.</p>
              <div className="flex gap-2">
                <input
                  type="number"
                  step="any"
                  min="0"
                  inputMode="decimal"
                  aria-label="Monto mínimo"
                  className={claseInput(errors.minimo)}
                  {...register("minimo", { setValueAs: numeroONulo })}
                />
                <select aria-label="Moneda del mínimo" className="input w-auto" {...register("minimo_moneda")}>
                  {MONEDAS_LISTA.map((m) => (
                    <option key={m} value={m}>
                      {MONEDAS[m]}
                    </option>
                  ))}
                </select>
              </div>
              {errors.minimo && <p className="input-error-text">{errors.minimo.message}</p>}
              <select aria-label="Contra qué se compara el mínimo" className="input" {...register("minimo_por")}>
                <option value="paquete">Por paquete: la diferencia queda en su precio</option>
                <option value="presupuesto">Por presupuesto: la diferencia va en un renglón aparte</option>
              </select>
            </fieldset>
          )}

          <label className="tap-target flex items-start gap-2">
            <input type="checkbox" className="mt-1" {...register("opcional")} />
            <span className="t-body-m">
              Opcional
              <span className="t-caption block">Quien presupuesta decide si va.</span>
            </span>
          </label>
        </form>
      </RightPanel>

      {rojo && (
        <ConfirmModal
          title="El % cambia 50 % o más"
          mensaje="Contra el valor anterior, el % cambia 50 % o más: revisá que no sea un error de tipeo. ¿Está bien?"
          confirmLabel="Sí, guardar"
          onClose={() => setRojo(null)}
          onConfirm={() => guardar({ ...rojo, confirmar_rojo: true })}
        />
      )}
    </>
  );
}
