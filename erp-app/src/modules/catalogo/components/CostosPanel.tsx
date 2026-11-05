"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { claseInput, Etiqueta } from "@/components/ui/Campo";
import { ConfirmModal } from "@/components/ui/Modal";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MONEDAS, MONEDAS_LISTA, formatMonto, type Moneda } from "@/lib/monedas";
import { CLASE_NIVEL, textoCambio } from "@/lib/niveles";
import { cargarCostos, revisarCostos } from "../actions";
import { POR_UNIDAD, hace, textoCosto } from "../etiquetas";
import { costosSchema, type CostosForm, type Costo, type NivelCosto, type Unidad } from "../types";

export type FilaCosto = { variante_id: string; nombre: string; unidad: Unidad; costo: Costo | null };

const numeroONulo = (v: unknown) => (v === "" || v === null ? null : Number(v));

// Uno o muchos: cada fila escrita es un valor nuevo con fecha, y se guardan juntas o ninguna. Antes de
// guardar se ve el cambio de cada una contra el vigente (15/25/50 %), y lo rojo se confirma de una vez.
export function CostosPanel({
  titulo,
  filas,
  monedaPrincipal,
  onClose,
}: {
  titulo: string;
  filas: FilaCosto[];
  monedaPrincipal: Moneda;
  onClose: () => void;
}) {
  const [niveles, setNiveles] = useState<NivelCosto[] | null>(null);
  const [rojo, setRojo] = useState<CostosForm | null>(null);
  const [pct, setPct] = useState("");
  const { register, handleSubmit, setValue, getValues, formState } = useForm<CostosForm>({
    resolver: zodResolver(costosSchema),
    defaultValues: {
      filas: filas.map((f) => ({
        variante_id: f.variante_id,
        costo: null,
        moneda: f.costo?.moneda ?? monedaPrincipal,
      })),
      confirmar_rojo: false,
    },
  });
  const { errors, isSubmitting } = formState;
  const nombre = new Map(filas.map((f) => [f.variante_id, f]));

  function aplicarPorcentaje() {
    const n = Number(pct.replace(",", "."));
    if (!pct.trim() || Number.isNaN(n)) {
      toast.error("Escribí un porcentaje, como 8 o −5");
      return;
    }
    filas.forEach((f, i) => {
      if (!f.costo) return;
      setValue(`filas.${i}.costo`, Math.round(f.costo.costo * (1 + n / 100) * 100) / 100, { shouldDirty: true });
      setValue(`filas.${i}.moneda`, f.costo.moneda, { shouldDirty: true });
    });
  }

  async function revisar(datos: CostosForm) {
    const r = await revisarCostos(datos);
    if (!r.success) toast.error(r.error);
    else setNiveles(r.niveles);
  }

  async function guardar(datos: CostosForm) {
    const r = await cargarCostos(datos);
    if ("pideConfirmar" in r) {
      setRojo(datos);
      return;
    }
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(r.cargadas === 1 ? "Costo guardado" : `${r.cargadas} costos guardados`);
    onClose();
  }

  return (
    <>
      <RightPanel
        title={titulo}
        subtitle="Sin IVA. Rige desde que se guarda."
        onClose={onClose}
        hayCambios={formState.isDirty}
        footer={
          niveles ? (
            <PiePanel
              confirmar="Guardar"
              enviando={isSubmitting}
              cancelar="Volver a editar"
              onCancelar={() => setNiveles(null)}
              onConfirmar={() => guardar(getValues())}
            />
          ) : (
            <PiePanel
              confirmar="Revisar"
              enCurso="Revisando…"
              enviando={isSubmitting}
              onCancelar={onClose}
              onConfirmar={handleSubmit(revisar)}
            />
          )
        }
      >
        <div className="flex flex-col gap-4 overflow-y-auto p-5">
          {niveles ? (
            <Revision niveles={niveles} nombre={(id) => nombre.get(id)?.nombre ?? ""} />
          ) : (
            <>
              {filas.length > 1 && (
                <div className="flex flex-wrap items-end gap-2">
                  <div className="flex-1">
                    <label htmlFor="costos-pct" className="t-label mb-1 block">
                      <Etiqueta texto="Cambiar todos los que tienen costo (%)" />
                    </label>
                    <input
                      id="costos-pct"
                      inputMode="decimal"
                      placeholder="8"
                      className="input"
                      value={pct}
                      onChange={(e) => setPct(e.target.value)}
                    />
                  </div>
                  <button type="button" className="btn btn-secondary" onClick={aplicarPorcentaje}>
                    Aplicar
                  </button>
                </div>
              )}
              {errors.filas?.root && <p className="input-error-text">{errors.filas.root.message}</p>}
              {errors.filas?.message && <p className="input-error-text">{errors.filas.message}</p>}
              <ul className="flex flex-col gap-3">
                {filas.map((f, i) => {
                  const error = errors.filas?.[i]?.costo;
                  return (
                    <li key={f.variante_id} className="flex flex-col gap-1 border-b border-border pb-3 last:border-b-0">
                      <p className="t-body-m font-medium">{f.nombre}</p>
                      <p className="t-caption">
                        {f.costo ? `${textoCosto(f.costo, f.unidad)} · ${hace(f.costo.desde)}` : "Sin costo"}
                      </p>
                      <div className="flex gap-2">
                        <input
                          type="number"
                          step="any"
                          min="0"
                          inputMode="decimal"
                          aria-label={`Costo nuevo de ${f.nombre}, por ${POR_UNIDAD[f.unidad]}`}
                          placeholder={`Nuevo, por ${POR_UNIDAD[f.unidad]}`}
                          className={claseInput(error)}
                          {...register(`filas.${i}.costo`, { setValueAs: numeroONulo })}
                        />
                        <select
                          aria-label={`Moneda de ${f.nombre}`}
                          className="input w-auto"
                          {...register(`filas.${i}.moneda`)}
                        >
                          {MONEDAS_LISTA.map((m) => (
                            <option key={m} value={m}>
                              {MONEDAS[m]}
                            </option>
                          ))}
                        </select>
                      </div>
                      {error && <p className="input-error-text">{error.message}</p>}
                    </li>
                  );
                })}
              </ul>
            </>
          )}
        </div>
      </RightPanel>

      {rojo && (
        <ConfirmModal
          title="Cambian 50 % o más"
          mensaje={`${textoRojas(niveles ?? [])} contra el costo vigente: revisá que no sea un error de tipeo. ¿Está bien?`}
          confirmLabel="Sí, guardar"
          onClose={() => setRojo(null)}
          onConfirm={() => guardar({ ...rojo, confirmar_rojo: true })}
        />
      )}
    </>
  );
}

function textoRojas(niveles: NivelCosto[]) {
  const rojas = niveles.filter((n) => n.nivel === "rojo").length;
  return rojas === 1 ? "1 fila cambia 50 % o más" : `${rojas} filas cambian 50 % o más`;
}

function Revision({ niveles, nombre }: { niveles: NivelCosto[]; nombre: (id: string) => string }) {
  const hayRojas = niveles.some((n) => n.nivel === "rojo");
  return (
    <>
      <p className="t-body-m">
        {niveles.length === 1 ? "Se guarda 1 costo" : `Se guardan ${niveles.length} costos`}
        {hayRojas && `; ${textoRojas(niveles)}`}.
      </p>
      <ul className="flex flex-col">
        {niveles.map((n) => (
          <li
            key={n.variante_id}
            className="flex items-baseline justify-between gap-2 border-b border-border py-2 last:border-b-0"
          >
            <div className="min-w-0">
              <p className="t-body-m truncate font-medium">{nombre(n.variante_id)}</p>
              <p className="t-caption">
                {n.anterior !== null && n.anterior_moneda
                  ? `${formatMonto(n.anterior, n.anterior_moneda)} → ${formatMonto(n.costo, n.moneda)}`
                  : `Primer costo: ${formatMonto(n.costo, n.moneda)}`}
              </p>
            </div>
            {n.anterior !== null && n.anterior_moneda === n.moneda && (
              <span className={`shrink-0 ${n.nivel ? CLASE_NIVEL[n.nivel] : "t-caption"}`}>
                {textoCambio(n.anterior, n.costo)}
              </span>
            )}
            {n.anterior !== null && n.anterior_moneda !== n.moneda && n.nivel && (
              <span className={`shrink-0 ${CLASE_NIVEL[n.nivel]}`}>Cambia de moneda</span>
            )}
          </li>
        ))}
      </ul>
    </>
  );
}
