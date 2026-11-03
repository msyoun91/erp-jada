"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { claseInput } from "@/components/ui/Campo";
import { guardarCondicion } from "../../actions";
import { condicionSchema, type Condicion, type CondicionForm } from "../../types";
import { SacarBoton } from "./Fila";

type De = { variable_id?: string; material_id?: string; opcion_id?: string };

// Las alertas y bloqueos de una variable, un material o una opción: el mensaje es lo que lee el vendedor.
export function CondicionesLista({
  versionId,
  de,
  condiciones,
}: {
  versionId: string;
  de: De;
  condiciones: Condicion[];
}) {
  const [editando, setEditando] = useState<string | null>(null);
  const propias = condiciones.filter(
    (c) =>
      (de.variable_id && c.variable_id === de.variable_id) ||
      (de.material_id && c.material_id === de.material_id) ||
      (de.opcion_id && c.opcion_id === de.opcion_id),
  );

  return (
    <section className="flex flex-col gap-2">
      <h4 className="t-label">Condiciones</h4>
      <p className="t-caption">
        Si se cumple, el vendedor lee el mensaje. Un bloqueo no deja usar el paquete. Ej: alto &gt; ancho × 2.
      </p>
      <ul className="flex flex-col gap-2">
        {propias.map((c) =>
          editando === c.id ? (
            <li key={c.id}>
              <CondicionForm versionId={versionId} de={de} condicion={c} onListo={() => setEditando(null)} />
            </li>
          ) : (
            <li key={c.id} className="flex items-start justify-between gap-2 rounded-md border border-border p-2">
              <button className="min-w-0 flex-1 text-left" onClick={() => setEditando(c.id)}>
                <p className="t-body-m font-mono">si {c.condicion}</p>
                <p className={`t-caption ${c.bloquea ? "text-error-text" : "text-warning-text"}`}>
                  {c.bloquea ? "Bloquea" : "Alerta"}: {c.mensaje}
                </p>
              </button>
              <SacarBoton tabla="catalogo_condiciones" id={c.id} que="la condición" />
            </li>
          ),
        )}
      </ul>
      {editando === "nueva" ? (
        <CondicionForm versionId={versionId} de={de} condicion={null} onListo={() => setEditando(null)} />
      ) : (
        <button className="btn btn-secondary btn-sm self-start" onClick={() => setEditando("nueva")}>
          Sumar condición
        </button>
      )}
    </section>
  );
}

function CondicionForm({
  versionId,
  de,
  condicion,
  onListo,
}: {
  versionId: string;
  de: De;
  condicion: Condicion | null;
  onListo: () => void;
}) {
  const { register, handleSubmit, formState } = useForm<CondicionForm>({
    resolver: zodResolver(condicionSchema),
    defaultValues: {
      id: condicion?.id ?? null,
      version_id: versionId,
      variable_id: de.variable_id ?? null,
      material_id: de.material_id ?? null,
      opcion_id: de.opcion_id ?? null,
      condicion: condicion?.condicion ?? "",
      mensaje: condicion?.mensaje ?? "",
      bloquea: condicion?.bloquea ?? false,
    },
  });
  const { errors, isSubmitting } = formState;

  return (
    <div className="flex flex-col gap-2 rounded-md border border-border p-2">
      <input
        aria-label="Condición"
        placeholder="ancho > 3000"
        className={`${claseInput(errors.condicion)} font-mono`}
        {...register("condicion")}
      />
      {errors.condicion && <p className="input-error-text">{errors.condicion.message}</p>}
      <input
        aria-label="Mensaje para el vendedor"
        placeholder="Mensaje para el vendedor"
        className={claseInput(errors.mensaje)}
        {...register("mensaje")}
      />
      {errors.mensaje && <p className="input-error-text">{errors.mensaje.message}</p>}
      <label className="tap-target flex items-center gap-2">
        <input type="checkbox" {...register("bloquea")} />
        <span className="t-body-m">Bloquea</span>
      </label>
      <div className="flex gap-2">
        <button
          type="button"
          className="btn btn-primary btn-sm"
          disabled={isSubmitting}
          onClick={handleSubmit(async (d) => {
            const r = await guardarCondicion(d);
            if (!r.success) toast.error(r.error);
            else onListo();
          })}
        >
          Guardar
        </button>
        <button type="button" className="btn btn-secondary btn-sm" onClick={onListo}>
          Cancelar
        </button>
      </div>
    </div>
  );
}
