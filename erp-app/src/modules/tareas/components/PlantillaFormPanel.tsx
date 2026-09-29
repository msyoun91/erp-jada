"use client";

import { useState } from "react";
import { useFieldArray, useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowDown, ArrowUp, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { ENTES, labelRol, type CodigoEnte } from "@/lib/entes";
import { guardarPlantilla } from "../actions";
import { nombreEnte, textoCompleta, textoCondicion, textoDisparo } from "../etiquetas";
import type { EnteSobre, PlantillaCompleta } from "../queries";
import { plantillaSchema, type PlantillaForm } from "../types";
import { AsignadoSelect } from "./AsignadoSelect";
import { Campo, claseInput } from "@/components/ui/Campo";
import { useTareas } from "./contexto";

const FORM_ID = "plantilla-form";

const pasoVacio = {
  titulo: "",
  descripcion: "",
  asignado_id: null,
  asignado_equipo_id: null,
  prioridad: "media" as const,
  vence_dias: "",
  espera_anterior: true,
  condicion: null,
  completa_evento: null,
  completa_valor: null,
};

// Un select por par de columnas: "evento:valor"; "" = ninguno.
type Opcion = { valor: string; label: string };

function partir(v: string): [string | null, string | null] {
  if (!v) return [null, null];
  const [a, b] = v.split(":");
  return [a, b || null];
}

// Lo guardado que ya no está entre las opciones (el admin sin el ente) se muestra igual.
function conActual(opciones: Opcion[], actual: string, label: string) {
  return !actual || opciones.some((o) => o.valor === actual) ? opciones : [...opciones, { valor: actual, label }];
}

function Opciones({ opciones }: { opciones: Opcion[] }) {
  return opciones.map((o) => (
    <option key={o.valor} value={o.valor}>
      {o.label}
    </option>
  ));
}

export function PlantillaFormPanel({
  plantilla,
  entes,
  onClose,
}: {
  plantilla?: PlantillaCompleta;
  entes: EnteSobre[];
  onClose: () => void;
}) {
  const { yo } = useTareas();
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    setValue,
    getValues,
    formState: { errors, isDirty },
  } = useForm<PlantillaForm>({
    resolver: zodResolver(plantillaSchema),
    defaultValues: {
      id: plantilla?.id,
      nombre: plantilla?.nombre ?? "",
      descripcion: plantilla?.descripcion ?? "",
      sobre: plantilla?.sobre ?? null,
      disparo_evento: plantilla?.disparo_evento === "alta" || plantilla?.disparo_evento === "estado" ? plantilla.disparo_evento : null,
      disparo_estado: plantilla?.disparo_estado ?? null,
      disparo_activo: plantilla?.disparo_activo ?? false,
      pasos: plantilla?.tareas_plantillas_pasos.map((p) => ({
        titulo: p.titulo,
        descripcion: p.descripcion ?? "",
        asignado_id: p.asignado_id,
        asignado_equipo_id: p.asignado_equipo_id,
        prioridad: p.prioridad,
        vence_dias: p.vence_dias ?? "",
        espera_anterior: p.espera_anterior,
        condicion: p.condicion,
        completa_evento:
          p.completa_evento === "relacion_alta" || p.completa_evento === "estado" ? p.completa_evento : null,
        completa_valor: p.completa_valor,
      })) ?? [pasoVacio],
    },
  });
  const { fields, append, remove, move } = useFieldArray({ control, name: "pasos" });
  const pasos = useWatch({ control, name: "pasos" });
  const [sobre, disparoEvento, disparoEstado, disparoActivo] = useWatch({
    control,
    name: ["sobre", "disparo_evento", "disparo_estado", "disparo_activo"],
  });

  // Los códigos de roles y datos, de `entes` (lo que la base acepta); los
  // labels y los estados, de `lib/entes.ts`.
  const ente = sobre ? entes.find((e) => e.codigo === sobre) : undefined;
  const labels = sobre ? ENTES[sobre as CodigoEnte] : undefined;
  const roles = ente?.roles ?? Object.keys(labels?.roles ?? {});
  const estados = Object.keys(labels?.estados ?? {});
  const datos = ente?.datos ?? Object.keys(labels?.datos ?? {});
  // Prende el disparo solo su dueño; el admin lo puede apagar (TA025).
  const mia = !plantilla || plantilla.dueno_id === yo;

  const disparoActual = disparoEvento ? `${disparoEvento}:${disparoEstado ?? ""}` : "";
  const opcionesDisparo = sobre
    ? conActual(
        [
          ...(ente?.disparos.includes("alta") ? [{ valor: "alta:", label: textoDisparo(sobre, "alta", null) }] : []),
          ...(ente?.disparos.includes("estado")
            ? estados.map((e) => ({ valor: `estado:${e}`, label: textoDisparo(sobre, "estado", e) }))
            : []),
        ],
        disparoActual,
        disparoEvento ? textoDisparo(sobre, disparoEvento, disparoEstado ?? null) : ""
      )
    : [];

  // Cambiar "Sobre" deja sin sentido el disparo y las condiciones (TA024).
  function cambiarSobre(nuevo: string) {
    const opciones = { shouldDirty: true };
    setValue("sobre", nuevo || null, opciones);
    setValue("disparo_evento", null, opciones);
    setValue("disparo_estado", null, opciones);
    setValue("disparo_activo", false, opciones);
    getValues("pasos").forEach((_, i) => {
      setValue(`pasos.${i}.condicion`, null, opciones);
      setValue(`pasos.${i}.completa_evento`, null, opciones);
      setValue(`pasos.${i}.completa_valor`, null, opciones);
    });
  }

  function insertar(i: number, marca: string) {
    const actual = getValues(`pasos.${i}.descripcion`) ?? "";
    const separador = actual === "" || /\s$/.test(actual) ? "" : " ";
    setValue(`pasos.${i}.descripcion`, `${actual}${separador}${marca}`, { shouldDirty: true });
  }

  async function onSubmit(data: PlantillaForm) {
    setEnviando(true);
    const result = await guardarPlantilla(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(plantilla ? "Plantilla guardada" : "Plantilla creada");
    onClose();
  }

  return (
    <RightPanel
      title={plantilla ? "Editar plantilla" : "Nueva plantilla"}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <div className="flex-1" />
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose} disabled={enviando}>
            Cancelar
          </button>
          <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : plantilla ? "Guardar" : "Crear plantilla"}
          </button>
        </>
      }
    >
      <form
        id={FORM_ID}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <Campo id="plantilla-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="plantilla-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>

        <Campo id="plantilla-descripcion" label="Descripción" error={errors.descripcion}>
          <textarea
            id="plantilla-descripcion"
            rows={2}
            className={claseInput(errors.descripcion)}
            {...register("descripcion")}
          />
        </Campo>

        <Campo id="plantilla-sobre" label="Sobre" error={errors.sobre}>
          <select id="plantilla-sobre" className="input" value={sobre ?? ""} onChange={(e) => cambiarSobre(e.target.value)}>
            <Opciones
              opciones={conActual(
                [{ valor: "", label: "Ninguno" }, ...entes.map((e) => ({ valor: e.codigo, label: nombreEnte(e.codigo) }))],
                sobre ?? "",
                nombreEnte(sobre ?? "")
              )}
            />
          </select>
        </Campo>
        {sobre && (
          <p className="t-caption -mt-2">Al usarla se elige {labels?.un ?? "el registro"}, y los pasos pueden nombrarlo.</p>
        )}

        {opcionesDisparo.length > 0 && (
          <Campo id="plantilla-disparo" label="Corre sola" error={errors.disparo_evento}>
            <div className="flex flex-wrap items-center gap-3">
              <select
                id="plantilla-disparo"
                className="input min-w-48 flex-1"
                value={disparoActual}
                onChange={(e) => {
                  const [evento, estado] = partir(e.target.value);
                  setValue("disparo_evento", evento === "alta" || evento === "estado" ? evento : null, { shouldDirty: true });
                  setValue("disparo_estado", estado, { shouldDirty: true });
                  if (!evento) setValue("disparo_activo", false, { shouldDirty: true });
                }}
              >
                <Opciones opciones={[{ valor: "", label: "Nunca: se usa a mano" }, ...opcionesDisparo]} />
              </select>
              {disparoEvento && (
                <label className="t-body-m flex items-center gap-2">
                  <input type="checkbox" disabled={!mia && !disparoActivo} {...register("disparo_activo")} />
                  Activa
                </label>
              )}
            </div>
          </Campo>
        )}
        {disparoEvento && (
          <p className="t-caption -mt-2">
            {disparoActivo
              ? `Corre sobre ${labels ? `cada ${labels.nombre.toLowerCase()}` : "cada registro"} de la que seas responsable; el hilo nace tuyo.`
              : "Apagada: no corre hasta que la actives."}
          </p>
        )}

        <p className="t-label">Pasos</p>
        {errors.pasos?.root && <p className="input-error-text">{errors.pasos.root.message}</p>}

        {fields.map((f, i) => {
          const e = errors.pasos?.[i];
          const paso = pasos?.[i];
          const espera = i > 0 && paso?.espera_anterior !== false;
          const completaActual = paso?.completa_evento ? `${paso.completa_evento}:${paso.completa_valor ?? ""}` : "";
          return (
            <fieldset key={f.id} className="flex flex-col gap-3 rounded-lg border border-border p-3">
              <div className="flex items-center gap-1">
                <legend className="t-label flex-1">Paso {i + 1}</legend>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  aria-label="Subir"
                  disabled={i === 0}
                  onClick={() => move(i, i - 1)}
                >
                  <ArrowUp size={14} />
                </button>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  aria-label="Bajar"
                  disabled={i === fields.length - 1}
                  onClick={() => move(i, i + 1)}
                >
                  <ArrowDown size={14} />
                </button>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm text-error-text"
                  aria-label="Quitar paso"
                  disabled={fields.length === 1}
                  onClick={() => remove(i)}
                >
                  <Trash2 size={14} />
                </button>
              </div>

              <Campo id={`pp-titulo-${i}`} label="Título" requerido error={e?.titulo}>
                <input id={`pp-titulo-${i}`} aria-required className={claseInput(e?.titulo)} {...register(`pasos.${i}.titulo`)} />
              </Campo>

              <Campo id={`pp-descripcion-${i}`} label="Descripción" error={e?.descripcion}>
                <textarea
                  id={`pp-descripcion-${i}`}
                  rows={2}
                  className={claseInput(e?.descripcion)}
                  {...register(`pasos.${i}.descripcion`)}
                />
              </Campo>
              {sobre && (
                <div className="-mt-2 flex flex-wrap gap-1" role="group" aria-label="Insertar en la descripción">
                  {[
                    { marca: "{@registro}", label: labels?.nombre ?? "El registro" },
                    ...roles.map((r) => ({ marca: `{@${r}}`, label: labelRol(sobre, r) })),
                    ...datos.map((d) => ({ marca: `{${d}}`, label: labels?.datos[d]?.label ?? d })),
                  ].map((c) => (
                    <button
                      key={c.marca}
                      type="button"
                      className="badge badge-neutral cursor-pointer"
                      title={c.marca}
                      onClick={() => insertar(i, c.marca)}
                    >
                      + {c.label}
                    </button>
                  ))}
                </div>
              )}

              <Campo id={`pp-asignado-${i}`} label="Asignado" error={e?.asignado_id}>
                <AsignadoSelect
                  id={`pp-asignado-${i}`}
                  vacio="Se elige al usarla"
                  invalido={!!e?.asignado_id}
                  value={{ asignado_id: paso?.asignado_id ?? null, asignado_equipo_id: paso?.asignado_equipo_id ?? null }}
                  onChange={(v) => {
                    setValue(`pasos.${i}.asignado_id`, v.asignado_id, { shouldDirty: true });
                    setValue(`pasos.${i}.asignado_equipo_id`, v.asignado_equipo_id, { shouldDirty: true });
                  }}
                />
              </Campo>

              <div className="flex gap-3">
                <div className="flex-1">
                  <Campo id={`pp-prioridad-${i}`} label="Prioridad" error={e?.prioridad}>
                    <select id={`pp-prioridad-${i}`} className="input" {...register(`pasos.${i}.prioridad`)}>
                      <option value="alta">Alta</option>
                      <option value="media">Media</option>
                      <option value="baja">Baja</option>
                    </select>
                  </Campo>
                </div>
                <div className="flex-1">
                  <Campo
                    id={`pp-dias-${i}`}
                    label={espera ? "Vence a los días de habilitarse" : "Vence a los días de usarla"}
                    error={e?.vence_dias}
                  >
                    <input
                      id={`pp-dias-${i}`}
                      type="number"
                      min={1}
                      className={claseInput(e?.vence_dias)}
                      {...register(`pasos.${i}.vence_dias`)}
                    />
                  </Campo>
                </div>
              </div>

              {sobre && (roles.length > 0 || estados.length > 0) && (
                <div className="flex flex-wrap gap-3">
                  {roles.length > 0 && (
                    <div className="min-w-40 flex-1">
                      <Campo id={`pp-condicion-${i}`} label="Entra" error={e?.condicion}>
                        <select
                          id={`pp-condicion-${i}`}
                          className="input"
                          value={paso?.condicion ?? ""}
                          onChange={(ev) => setValue(`pasos.${i}.condicion`, ev.target.value || null, { shouldDirty: true })}
                        >
                          <Opciones
                            opciones={conActual(
                              [
                                { valor: "", label: "Siempre" },
                                ...roles.map((r) => ({ valor: r, label: textoCondicion(sobre, r) })),
                                ...roles.map((r) => ({ valor: `!${r}`, label: textoCondicion(sobre, `!${r}`) })),
                              ],
                              paso?.condicion ?? "",
                              textoCondicion(sobre, paso?.condicion ?? "")
                            )}
                          />
                        </select>
                      </Campo>
                    </div>
                  )}
                  <div className="min-w-40 flex-1">
                    <Campo id={`pp-completa-${i}`} label="Se completa" error={e?.completa_evento}>
                      <select
                        id={`pp-completa-${i}`}
                        className="input"
                        value={completaActual}
                        onChange={(ev) => {
                          const [evento, valor] = partir(ev.target.value);
                          setValue(
                            `pasos.${i}.completa_evento`,
                            evento === "relacion_alta" || evento === "estado" ? evento : null,
                            { shouldDirty: true }
                          );
                          setValue(`pasos.${i}.completa_valor`, valor, { shouldDirty: true });
                        }}
                      >
                        <Opciones
                          opciones={conActual(
                            [
                              { valor: "", label: "A mano" },
                              ...roles.map((r) => ({ valor: `relacion_alta:${r}`, label: textoCompleta(sobre, "relacion_alta", r) })),
                              ...estados.map((s) => ({ valor: `estado:${s}`, label: textoCompleta(sobre, "estado", s) })),
                            ],
                            completaActual,
                            paso?.completa_evento ? textoCompleta(sobre, paso.completa_evento, paso.completa_valor ?? "") : ""
                          )}
                        />
                      </select>
                    </Campo>
                  </div>
                </div>
              )}

              {i > 0 && (
                <label className="t-body-m flex items-center gap-2">
                  <input type="checkbox" {...register(`pasos.${i}.espera_anterior`)} />
                  Espera al paso anterior
                </label>
              )}
            </fieldset>
          );
        })}

        <button type="button" className="btn btn-secondary btn-sm self-start" onClick={() => append(pasoVacio)}>
          <Plus size={14} />
          Sumar paso
        </button>
      </form>
    </RightPanel>
  );
}
