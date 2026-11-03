"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { guardarVersionDatos, marcarColorBase, sumarColorVersion } from "../../actions";
import { versionDatosSchema, type Categoria, type Color, type Version, type VersionDatosForm } from "../../types";
import { SacarBoton } from "./Fila";

// Nombre y categoría son de la versión: es lo que el gerente aprueba y el vendedor lee.
export function DatosVersion({
  version,
  categorias,
  colores,
}: {
  version: Version;
  categorias: Categoria[];
  colores: Color[];
}) {
  const [colorNuevo, setColorNuevo] = useState("");
  const { register, handleSubmit, formState, reset } = useForm<VersionDatosForm>({
    resolver: zodResolver(versionDatosSchema),
    defaultValues: { id: version.id, nombre: version.nombre, categoria_id: version.categoria_id },
  });
  const { errors, isSubmitting, isDirty } = formState;
  const sumables = colores.filter((c) => c.activo && !version.colores.some((v) => v.color_id === c.id));

  async function sumarColor() {
    const r = await sumarColorVersion({ version_id: version.id, color_id: colorNuevo });
    if (!r.success) toast.error(r.error);
    else setColorNuevo("");
  }

  async function base(id: string) {
    const r = await marcarColorBase({ version_id: version.id, id });
    if (!r.success) toast.error(r.error);
  }

  return (
    <section className="card flex flex-col gap-4">
      <form
        className="flex flex-col gap-3"
        onSubmit={handleSubmit(async (d) => {
          const r = await guardarVersionDatos(d);
          if (!r.success) toast.error(r.error);
          else {
            toast.success("Datos guardados");
            reset(d);
          }
        })}
      >
        <Campo id="version-nombre" label="Nombre del paquete" requerido error={errors.nombre}>
          <input id="version-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo id="version-categoria" label="Categoría" requerido error={errors.categoria_id}>
          <select id="version-categoria" aria-required className="input" {...register("categoria_id")}>
            {categorias
              .filter((c) => c.activo || c.id === version.categoria_id)
              .map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre}
                  {c.activo ? "" : " (de baja)"}
                </option>
              ))}
          </select>
        </Campo>
        {isDirty && (
          <button type="submit" className="btn btn-primary self-start" disabled={isSubmitting}>
            Guardar nombre y categoría
          </button>
        )}
      </form>

      <div className="flex flex-col gap-2">
        <h3 className="t-label">Colores que ofrece</h3>
        <p className="t-caption">
          El base viene elegido para el vendedor. En cada color se deja de ofrecer lo que no se arma en él.
        </p>
        {version.colores.length === 0 && <p className="t-body-m">Sin colores: solo insumos de color indistinto.</p>}
        <ul className="flex flex-col">
          {version.colores.map((c) => (
            <li key={c.id} className="flex items-center gap-2 border-b border-border py-1.5 last:border-b-0">
              <span className="t-body-m flex-1">{c.nombre}</span>
              {c.base ? (
                <span className="badge badge-info">Base</span>
              ) : (
                <button className="btn btn-ghost btn-sm" onClick={() => base(c.id)}>
                  Hacer base
                </button>
              )}
              <SacarBoton tabla="catalogo_versiones_colores" id={c.id} que={`el ${c.nombre}`} />
            </li>
          ))}
        </ul>
        {sumables.length > 0 && (
          <div className="flex gap-2">
            <select
              aria-label="Color para sumar"
              className="input"
              value={colorNuevo}
              onChange={(e) => setColorNuevo(e.target.value)}
            >
              <option value="">Sumar un color…</option>
              {sumables.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre}
                </option>
              ))}
            </select>
            <button className="btn btn-secondary shrink-0" disabled={!colorNuevo} onClick={sumarColor}>
              Sumar
            </button>
          </div>
        )}
      </div>
    </section>
  );
}
