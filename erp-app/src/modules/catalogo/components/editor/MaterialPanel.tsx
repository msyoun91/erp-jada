"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarMaterial, guardarOpcion, sacar } from "../../actions";
import { materialSchema, type Contenido, type Material, type MaterialForm, type Opcion } from "../../types";
import { CondicionesLista } from "./CondicionesLista";
import { Fila } from "./Fila";
import { InsumoSelect, type InsumosPorId } from "./InsumoSelect";
import { Nombres } from "./Nombres";
import { OpcionPanel } from "./OpcionPanel";

const TIPO: Record<MaterialForm["tipo"], string> = {
  unico: "Único: un insumo o servicio fijo",
  elige_vendedor: "Múltiple: lo elige el vendedor",
  elige_sistema: "Múltiple: lo define el sistema con una regla",
  sigue: "Sigue la elección de otro (sincronizado o combo)",
};

export function MaterialPanel({
  versionId,
  material,
  piezaId,
  orden,
  contenido,
  insumos,
  nombres,
  onCreado,
  onClose,
}: {
  versionId: string;
  material: Material | null;
  piezaId: string;
  orden: number;
  contenido: Contenido;
  insumos: InsumosPorId;
  nombres: string[];
  onCreado: (id: string) => void;
  onClose: () => void;
}) {
  const [opcion, setOpcion] = useState<Opcion | "nueva" | null>(null);
  const { register, handleSubmit, control, formState } = useForm<MaterialForm>({
    resolver: zodResolver(materialSchema),
    defaultValues: material
      ? { ...material, version_id: versionId }
      : { id: null, version_id: versionId, pieza_id: piezaId, orden, tipo: "unico", cantidad: "1", cuenta_peso: true },
  });
  const { errors, isSubmitting } = formState;
  const [tipo, insumoId] = useWatch({ control, name: ["tipo", "insumo_id"] });
  const insumo = insumos.get(insumoId ?? "");
  const opciones = material ? contenido.opciones.filter((o) => o.material_id === material.id) : [];
  const conArea = tipo !== "unico" || insumo?.unidad === "m2";
  const esServicio = tipo === "unico" && insumo?.tipo === "servicio";
  const seguibles = contenido.materiales.filter(
    (m) => m.id !== material?.id && (m.tipo === "elige_vendedor" || m.tipo === "elige_sistema"),
  );

  async function guardar(d: MaterialForm) {
    const r = await guardarMaterial(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success("Material guardado");
    if (!material && d.tipo !== "unico") onCreado(r.id);
    else onClose();
  }

  const formulas = [
    {
      campo: "medida",
      label:
        tipo === "unico" && insumo?.unidad === "u"
          ? "Medida de corte (mm), opcional: se cobra la cantidad"
          : tipo === "unico" && insumo?.unidad === "m2"
            ? null
            : "Medida (mm)",
    },
    { campo: "ancho", label: conArea && !esServicio ? "Ancho (mm)" : null },
    { campo: "alto", label: conArea && !esServicio ? "Alto (mm)" : null },
    { campo: "area", label: conArea ? "Área (mm²), solo si no es un rectángulo" : null },
    { campo: "cantidad", label: "Cantidad de piezas iguales" },
  ] as const;

  return (
    <>
      <RightPanel
        title={material ? "Material" : "Nuevo material"}
        subtitle="Las fórmulas dan mm; el sistema pasa a la unidad del insumo."
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
            <Campo id="mat-tipo" label="Tipo" requerido error={errors.tipo}>
              <select id="mat-tipo" className="input" {...register("tipo")}>
                {Object.entries(TIPO).map(([valor, label]) => (
                  <option key={valor} value={valor}>
                    {label}
                  </option>
                ))}
              </select>
            </Campo>

            {tipo === "unico" ? (
              <Campo id="mat-insumo" label="Insumo o servicio fijo" requerido error={errors.insumo_id}>
                <InsumoSelect
                  id="mat-insumo"
                  insumos={insumos}
                  actual={material?.insumo_id}
                  registro={register("insumo_id")}
                />
              </Campo>
            ) : (
              <Campo id="mat-nombre" label="Nombre que lee el vendedor" requerido error={errors.nombre}>
                <input id="mat-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
              </Campo>
            )}

            {tipo === "elige_sistema" && (
              <Campo
                id="mat-eleccion"
                label="Regla: termina en una opción o en ninguno"
                requerido
                error={errors.eleccion}
              >
                <textarea
                  id="mat-eleccion"
                  rows={3}
                  placeholder="si [peso Hoja] > 40 entonces [Rueda 80kg] si no [Rueda 40kg]"
                  className={`${claseInput(errors.eleccion)} font-mono`}
                  {...register("eleccion")}
                />
              </Campo>
            )}

            {tipo === "sigue" && (
              <Campo id="mat-sigue" label="Sigue a" requerido error={errors.sigue_material_id}>
                <select id="mat-sigue" className="input" {...register("sigue_material_id")}>
                  <option value="">Elegí un material múltiple</option>
                  {seguibles.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.nombre} · {contenido.piezas.find((p) => p.id === m.pieza_id)?.nombre}
                    </option>
                  ))}
                </select>
              </Campo>
            )}

            {tipo === "elige_vendedor" && (
              <>
                <label className="tap-target flex items-center gap-2">
                  <input type="checkbox" {...register("sin_eleccion")} />
                  <span className="t-body-m">Permite &quot;sin elección&quot;</span>
                </label>
                <label className="tap-target flex items-center gap-2">
                  <input type="checkbox" {...register("secundario")} />
                  <span className="t-body-m">Secundario: va plegado en &quot;Más opciones&quot;</span>
                </label>
              </>
            )}

            {formulas.map(({ campo, label }) =>
              label ? (
                <Campo key={campo} id={`mat-${campo}`} label={label} error={errors[campo]}>
                  <input
                    id={`mat-${campo}`}
                    className={`${claseInput(errors[campo])} font-mono`}
                    {...register(campo)}
                  />
                </Campo>
              ) : null,
            )}
            {tipo !== "unico" && (
              <p className="t-caption">
                Las opciones heredan lo que no traen: la medida, solo si tienen la misma unidad.
              </p>
            )}
            <Nombres nombres={nombres} />

            {!esServicio && (
              <fieldset className="flex flex-col gap-1">
                <legend className="t-label mb-1">En la pieza</legend>
                <label className="tap-target flex items-center gap-2">
                  <input type="checkbox" {...register("cuenta_peso")} />
                  <span className="t-body-m">Cuenta para el peso</span>
                </label>
                <label className="tap-target flex items-center gap-2">
                  <input type="checkbox" {...register("cuenta_espesor")} />
                  <span className="t-body-m">Cuenta para el espesor</span>
                </label>
              </fieldset>
            )}
          </form>

          {material && (material.tipo === "elige_vendedor" || material.tipo === "elige_sistema") && (
            <section className="flex flex-col gap-2">
              <h4 className="t-label">Opciones</h4>
              {opciones.length === 0 && <p className="t-body-m text-warning-text">Sin opciones todavía.</p>}
              <ul className="flex flex-col">
                {opciones.map((o) => (
                  <Fila
                    key={o.id}
                    titulo={`${insumos.get(o.insumo_id ?? "")?.nombre ?? "—"}${o.predeterminada ? " · predeterminada" : ""}`}
                    detalle={[o.medida, o.ancho && o.alto && `${o.ancho} × ${o.alto}`, o.cantidad && `× ${o.cantidad}`]
                      .filter(Boolean)
                      .join(" · ")}
                    onAbrir={() => setOpcion(o)}
                    tabla="catalogo_opciones"
                    id={o.id}
                    hermanos={opciones.map((x) => x.id)}
                    que="la opción"
                  />
                ))}
              </ul>
              <button className="btn btn-secondary btn-sm self-start" onClick={() => setOpcion("nueva")}>
                Sumar opción
              </button>
            </section>
          )}

          {material?.tipo === "sigue" && material.sigue_material_id && (
            <Parejas versionId={versionId} material={material} contenido={contenido} insumos={insumos} />
          )}

          {material && (
            <CondicionesLista
              versionId={versionId}
              de={{ material_id: material.id }}
              condiciones={contenido.condiciones}
            />
          )}
        </div>
      </RightPanel>

      {opcion && material && (
        <OpcionPanel
          versionId={versionId}
          materialId={material.id}
          opcion={opcion === "nueva" ? null : opcion}
          orden={opciones.length}
          conPredeterminada={material.tipo !== "sigue"}
          insumos={insumos}
          condiciones={contenido.condiciones}
          nombres={nombres}
          onClose={() => setOpcion(null)}
        />
      )}
    </>
  );
}

// Una pareja por cada opción del que elige: un insumo, "ninguna" (no da fila) o vacía, que frena el envío.
// El sincronizado es un combo donde cada pareja es el mismo insumo.
function Parejas({
  versionId,
  material,
  contenido,
  insumos,
}: {
  versionId: string;
  material: Material;
  contenido: Contenido;
  insumos: InsumosPorId;
}) {
  const [pendiente, setPendiente] = useState(false);
  const delQueElige = contenido.opciones.filter((o) => o.material_id === material.sigue_material_id);
  const propias = contenido.opciones.filter((o) => o.material_id === material.id);

  async function elegir(sigue: Opcion, valor: string) {
    const actual = propias.find((p) => p.sigue_opcion_id === sigue.id);
    setPendiente(true);
    const r =
      valor === ""
        ? actual
          ? await sacar({ tabla: "catalogo_opciones", id: actual.id })
          : { success: true as const }
        : await guardarOpcion({
            id: actual?.id ?? null,
            version_id: versionId,
            material_id: material.id,
            sigue_opcion_id: sigue.id,
            insumo_id: valor === "ninguna" ? null : valor,
          });
    setPendiente(false);
    if (!r.success) toast.error(r.error);
  }

  async function sincronizar() {
    for (const o of delQueElige) if (o.insumo_id) await elegir(o, o.insumo_id);
  }

  return (
    <section className="flex flex-col gap-2">
      <h4 className="t-label">Parejas</h4>
      <p className="t-caption">El vendedor elige una vez, en el otro material: esta queda con la pareja.</p>
      <ul className="flex flex-col gap-2">
        {delQueElige.map((o) => {
          const actual = propias.find((p) => p.sigue_opcion_id === o.id);
          const valor = actual ? (actual.insumo_id ?? "ninguna") : "";
          return (
            <li key={o.id} className="flex flex-col gap-1">
              <span className="t-body-m">{insumos.get(o.insumo_id ?? "")?.nombre ?? "—"} →</span>
              <InsumoSelect
                insumos={insumos}
                value={valor}
                onChange={(v) => elegir(o, v)}
                vacio="Vacía: frena el envío"
                extra={<option value="ninguna">Ninguna: no lleva</option>}
              />
            </li>
          );
        })}
      </ul>
      {delQueElige.length > 0 && (
        <button className="btn btn-secondary btn-sm self-start" onClick={sincronizar} disabled={pendiente}>
          Mismas opciones (sincronizado)
        </button>
      )}
    </section>
  );
}
