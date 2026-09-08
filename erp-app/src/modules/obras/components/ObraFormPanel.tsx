"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { buscarDuplicadosObra, crearObra, editarObra } from "../actions";
import {
  crearObraSchema,
  ESTADOS_OBRA,
  LABEL_ESTADO,
  LABEL_MOTIVO_PERDIDA,
  LABEL_ORIGEN,
  LABEL_PROVINCIA,
  LABEL_TIPO,
  MOTIVOS_PERDIDA,
  ORIGENES_OBRA,
  PROVINCIAS,
  TIPOS_OBRA,
  type CrearObraForm,
  type DuplicadoObra,
  type Obra,
} from "../types";
import { AvisoDuplicadosObra } from "./AvisoDuplicados";

export function ObraFormPanel({ obra, onClose }: { obra?: Obra; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const [duplicados, setDuplicados] = useState<DuplicadoObra[]>([]);

  const {
    register,
    handleSubmit,
    control,
    getValues,
    formState: { errors, isDirty },
  } = useForm<CrearObraForm>({
    resolver: zodResolver(crearObraSchema),
    defaultValues: obra
      ? {
          nombre: obra.nombre,
          tipo: obra.tipo,
          estado: obra.estado,
          direccion: obra.direccion,
          localidad: obra.localidad,
          provincia: obra.provincia,
          origen: obra.origen,
          observaciones: obra.observaciones,
          motivo_perdida: obra.motivo_perdida,
          detalle_perdida: obra.detalle_perdida,
        }
      : { estado: "idea", tipo: "edificio" },
  });

  // useWatch y no watch(): watch() devuelve una función no memoizable y el
  // React Compiler saltea la optimización del componente entero.
  const estado = useWatch({ control, name: "estado" });
  const motivo = useWatch({ control, name: "motivo_perdida" });

  // Al salir del nombre, no mientras escribe: una consulta por tecla no aporta
  // nada y el aviso solo tiene sentido con el nombre completo.
  // Corre también al editar: renombrar una obra hacia una que ya existe es
  // tan duplicado como cargarla dos veces. `obra?.id` la excluye del
  // resultado, que si no se encontraría a sí misma con similitud 1.
  async function chequearDuplicados() {
    const { nombre, direccion, localidad } = getValues();
    if (!nombre?.trim()) return;
    setDuplicados(
      await buscarDuplicadosObra(
        nombre,
        direccion ?? undefined,
        localidad ?? undefined,
        obra?.id,
      ),
    );
  }

  async function onSubmit(data: CrearObraForm) {
    setEnviando(true);
    const result = obra ? await editarObra({ ...data, id: obra.id }) : await crearObra(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    // El aviso de duplicados advierte; el trigger de la base decide. Si la
    // obra quedó congelada hay que decirlo acá, porque hasta que la aprueben
    // no se le puede vincular nada.
    if (!obra && "pendiente" in result && result.pendiente) {
      toast.warning("Obra creada, pendiente de autorización: se parece a una que ya existe");
    } else {
      toast.success(obra ? "Obra actualizada" : "Obra creada");
    }
    onClose();
  }

  return (
    <RightPanel
      title={obra ? "Modificar obra" : "Nueva obra"}
      subtitle={obra?.nombre}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-obra" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : obra ? "Guardar cambios" : "Crear obra"}
          </button>
        </>
      }
    >
      <form
        id="form-obra"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        {duplicados.length > 0 && <AvisoDuplicadosObra duplicados={duplicados} />}

        <div>
          <label className="t-label t-label-req mb-1 block">Nombre</label>
          <input
            className={`input ${errors.nombre ? "input-error" : ""}`}
            placeholder="Edificio próximo a Cabildo"
            {...register("nombre", { onBlur: chequearDuplicados })}
          />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
          <p className="t-caption mt-1">No hace falta que sea el nombre oficial del proyecto.</p>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label t-label-req mb-1 block">Tipo</label>
            <select className="input" {...register("tipo")}>
              {TIPOS_OBRA.map((t) => (
                <option key={t} value={t}>
                  {LABEL_TIPO[t]}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="t-label t-label-req mb-1 block">Estado</label>
            <select className="input" {...register("estado")}>
              {ESTADOS_OBRA.map((e) => (
                <option key={e} value={e}>
                  {LABEL_ESTADO[e]}
                </option>
              ))}
            </select>
          </div>
        </div>

        {estado === "perdida" && (
          <>
            <div>
              <label className="t-label t-label-req mb-1 block">Motivo de pérdida</label>
              <select className={`input ${errors.motivo_perdida ? "input-error" : ""}`} {...register("motivo_perdida")}>
                <option value="">Elegí un motivo…</option>
                {MOTIVOS_PERDIDA.map((m) => (
                  <option key={m} value={m}>
                    {LABEL_MOTIVO_PERDIDA[m]}
                  </option>
                ))}
              </select>
              {errors.motivo_perdida && (
                <p className="input-error-text">{errors.motivo_perdida.message}</p>
              )}
            </div>
            <div>
              <label className={`t-label mb-1 block ${motivo === "otro" ? "t-label-req" : ""}`}>
                Detalle
              </label>
              <textarea
                rows={2}
                className={`input ${errors.detalle_perdida ? "input-error" : ""}`}
                {...register("detalle_perdida")}
              />
              {errors.detalle_perdida && (
                <p className="input-error-text">{errors.detalle_perdida.message}</p>
              )}
            </div>
          </>
        )}

        <div>
          <label className="t-label mb-1 block">Dirección</label>
          <input className="input" {...register("direccion", { onBlur: chequearDuplicados })} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Localidad</label>
            <input className="input" {...register("localidad", { onBlur: chequearDuplicados })} />
          </div>
          <div>
            <label className="t-label mb-1 block">Provincia</label>
            <select className="input" {...register("provincia")}>
              <option value="">Sin especificar</option>
              {PROVINCIAS.map((p) => (
                <option key={p} value={p}>
                  {LABEL_PROVINCIA[p]}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="t-label mb-1 block">Origen</label>
          <select className="input" {...register("origen")}>
            <option value="">Sin especificar</option>
            {ORIGENES_OBRA.map((o) => (
              <option key={o} value={o}>
                {LABEL_ORIGEN[o]}
              </option>
            ))}
          </select>
          <p className="t-caption mt-1">
            De dónde salió el dato. No crea vínculo con ninguna empresa.
          </p>
        </div>

        <div>
          <label className="t-label mb-1 block">Observaciones</label>
          <textarea rows={3} className="input" {...register("observaciones")} />
        </div>
      </form>
    </RightPanel>
  );
}
