"use client";

import { useRef, useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarMaterial, guardarOpcion, sacar } from "../../actions";
import { formulaAparte } from "../../etiquetas";
import { materialSchema, type Contenido, type Material, type MaterialForm, type Opcion } from "../../types";
import { CamposMedida } from "./CamposMedida";
import { CondicionesLista } from "./CondicionesLista";
import { Fila } from "./Fila";
import { InsumoSelect, type InsumosPorId } from "./InsumoSelect";
import { ArmarRegla, Nombres } from "./Nombres";
import { OpcionPanel } from "./OpcionPanel";

const TIPO: Record<MaterialForm["tipo"], string> = {
  unico: "Único: un insumo o servicio fijo",
  elige_vendedor: "Múltiple: lo elige el vendedor",
  elige_sistema: "Múltiple: lo define el sistema con una regla",
  sigue: "Sigue la elección de otro (sincronizado o combo)",
};

function detalleOpcion(o: Opcion) {
  return [
    o.medida,
    o.ancho && o.alto && `${formulaAparte(o.ancho)} × ${formulaAparte(o.alto)}`,
    o.area && `área ${formulaAparte(o.area)}`,
    o.cantidad && `× ${formulaAparte(o.cantidad)}`,
  ]
    .filter(Boolean)
    .join(" · ");
}

export function MaterialPanel({
  versionId,
  material,
  piezaId,
  orden,
  contenido,
  insumos,
  nombres,
  abrirOpcion = false,
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
  // Recién creado con "Sumar opción": el panel se vuelve a montar con el material y sigue en esa opción.
  abrirOpcion?: boolean;
  onCreado: (id: string, sumarOpcion: boolean) => void;
  onClose: () => void;
}) {
  const [opcion, setOpcion] = useState<Opcion | "nueva" | null>(abrirOpcion ? "nueva" : null);
  const regla = useRef<HTMLTextAreaElement | null>(null);
  const { register, handleSubmit, control, formState, getValues, setValue, reset } = useForm<MaterialForm>({
    resolver: zodResolver(materialSchema),
    defaultValues: material
      ? { ...material, version_id: versionId }
      : { id: null, version_id: versionId, pieza_id: piezaId, orden, tipo: "unico", cantidad: "1", cuenta_peso: true },
  });
  const { errors, isSubmitting } = formState;
  const { ref: registrarRegla, ...campoRegla } = register("eleccion");
  const [tipo, insumoId] = useWatch({ control, name: ["tipo", "insumo_id"] });
  const insumo = insumos.get(insumoId ?? "");
  const opciones = material ? contenido.opciones.filter((o) => o.material_id === material.id) : [];
  const sueltas = opciones.filter((o) => !o.sigue_opcion_id);
  const esServicio = tipo === "unico" && insumo?.tipo === "servicio";

  // Un múltiple no tiene unidad: la tiene cada opción.
  const usados =
    tipo === "unico" ? (insumo ? [insumo] : []) : opciones.flatMap((o) => insumos.get(o.insumo_id ?? "") ?? []);

  const seguibles = contenido.materiales.filter(
    (m) => m.id !== material?.id && (m.tipo === "elige_vendedor" || m.tipo === "elige_sistema"),
  );

  const seguida = opcion && opcion !== "nueva" ? contenido.opciones.find((o) => o.id === opcion.sigue_opcion_id) : null;

  async function grabar(d: MaterialForm) {
    const r = await guardarMaterial(d);
    if (!r.success) {
      toast.error(r.error);
      return null;
    }
    toast.success("Material guardado");
    return r.id;
  }

  async function guardar(d: MaterialForm) {
    const id = await grabar(d);
    if (!id) return;
    if (!material && d.tipo !== "unico") onCreado(id, false);
    else onClose();
  }

  // Una opción cuelga de un material guardado y de ese tipo: si todavía no lo está, se guarda solo antes de abrirla.
  function sumarOpcion() {
    if (material?.tipo === tipo) {
      setOpcion("nueva");
      return;
    }
    void handleSubmit(async (d) => {
      const id = await grabar(d);
      if (!id) return;
      if (!material) {
        onCreado(id, true);
        return;
      }
      reset(getValues());
      setOpcion("nueva");
    })();
  }

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
          </form>

          {(tipo === "elige_vendedor" || tipo === "elige_sistema") && (
            <section className="flex flex-col gap-2">
              <h4 className="t-label">Opciones</h4>
              {opciones.length === 0 && <p className="t-body-m text-warning-text">Todavía no hay ninguna.</p>}
              <ul className="flex flex-col">
                {opciones.map((o) => (
                  <Fila
                    key={o.id}
                    titulo={`${insumos.get(o.insumo_id ?? "")?.nombre ?? "—"}${o.predeterminada ? " · predeterminada" : ""}`}
                    detalle={detalleOpcion(o)}
                    onAbrir={() => setOpcion(o)}
                    tabla="catalogo_opciones"
                    id={o.id}
                    hermanos={opciones.map((x) => x.id)}
                    que="la opción"
                  />
                ))}
              </ul>
              <button className="btn btn-secondary btn-sm self-start" onClick={sumarOpcion} disabled={isSubmitting}>
                Sumar opción
              </button>
            </section>
          )}

          <form onSubmit={handleSubmit(guardar)} className="flex flex-col gap-4">
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
                  {...campoRegla}
                  ref={(el) => {
                    registrarRegla(el);
                    regla.current = el;
                  }}
                />
                <ArmarRegla
                  textarea={regla}
                  onCambio={(v) => setValue("eleccion", v, { shouldDirty: true })}
                  opciones={opciones.flatMap((o) => insumos.get(o.insumo_id ?? "")?.nombre ?? [])}
                  nombres={nombres.filter((n) => n !== material?.nombre)}
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
              <label className="tap-target flex items-center gap-2">
                <input type="checkbox" {...register("sin_eleccion")} />
                <span className="t-body-m">Permite &quot;sin elección&quot;</span>
              </label>
            )}
            {(tipo === "elige_vendedor" || tipo === "sigue") && (
              <label className="tap-target flex items-center gap-2">
                <input type="checkbox" {...register("secundario")} />
                <span className="t-body-m">Secundario: va plegado en &quot;Más opciones&quot;</span>
              </label>
            )}

            <CamposMedida
              usados={usados}
              conValor={(c) => Boolean(material?.[c] || getValues(c))}
              campo={(c, label) => (
                <Campo id={`mat-${c}`} label={label} error={errors[c]}>
                  <input id={`mat-${c}`} className={`${claseInput(errors[c])} font-mono`} {...register(c)} />
                </Campo>
              )}
            />
            <Campo id="mat-cantidad" label="Cantidad de piezas iguales" error={errors.cantidad}>
              <input
                id="mat-cantidad"
                className={`${claseInput(errors.cantidad)} font-mono`}
                {...register("cantidad")}
              />
            </Campo>
            {tipo !== "unico" && (
              <p className="t-caption">
                {usados.length > 0
                  ? "Las opciones heredan lo que no traen."
                  : "Las medidas aparecen al sumar una opción, según su unidad."}
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

          {material?.tipo === "sigue" && material.sigue_material_id && (
            <>
              <Parejas
                versionId={versionId}
                material={material}
                contenido={contenido}
                insumos={insumos}
                onAbrir={setOpcion}
              />
              <section className="flex flex-col gap-2">
                <h4 className="t-label">Opciones sueltas</h4>
                <p className="t-caption">No son pareja de nadie: el vendedor las elige de la lista, nunca se completan solas.</p>
                <ul className="flex flex-col">
                  {sueltas.map((o) => (
                    <Fila
                      key={o.id}
                      titulo={insumos.get(o.insumo_id ?? "")?.nombre ?? "—"}
                      detalle={detalleOpcion(o)}
                      onAbrir={() => setOpcion(o)}
                      tabla="catalogo_opciones"
                      id={o.id}
                      hermanos={sueltas.map((x) => x.id)}
                      que="la opción"
                    />
                  ))}
                </ul>
                <button className="btn btn-secondary btn-sm self-start" onClick={() => setOpcion("nueva")}>
                  Sumar opción suelta
                </button>
              </section>
            </>
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
          parejaDe={seguida ? (insumos.get(seguida.insumo_id ?? "")?.nombre ?? "—") : undefined}
          insumos={insumos}
          condiciones={contenido.condiciones}
          nombres={nombres}
          onClose={() => setOpcion(null)}
        />
      )}
    </>
  );
}

// Con el teclado, cada flecha es un cambio y pasa por "Vacía" y "Ninguna", que borran las fórmulas: se guarda lo que queda quieto.
function ParejaSelect({
  insumos,
  valor,
  onElegir,
}: {
  insumos: InsumosPorId;
  valor: string;
  onElegir: (v: string) => Promise<void>;
}) {
  const [borrador, setBorrador] = useState<string | null>(null);
  const espera = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const guardando = useRef(false);

  function cambiar(v: string) {
    if (guardando.current) return;
    setBorrador(v);
    clearTimeout(espera.current);
    espera.current = setTimeout(async () => {
      guardando.current = true;
      if (v !== valor) await onElegir(v);
      guardando.current = false;
      setBorrador(null);
    }, 500);
  }

  return (
    <InsumoSelect
      insumos={insumos}
      value={borrador ?? valor}
      onChange={cambiar}
      vacio="Vacía: frena el envío"
      extra={<option value="ninguna">Ninguna: no lleva</option>}
    />
  );
}

// Una pareja por cada opción del que elige: un insumo, "ninguna" (no da fila) o vacía, que frena el envío.
// El sincronizado es un combo donde cada pareja es el mismo insumo.
function Parejas({
  versionId,
  material,
  contenido,
  insumos,
  onAbrir,
}: {
  versionId: string;
  material: Material;
  contenido: Contenido;
  insumos: InsumosPorId;
  onAbrir: (o: Opcion) => void;
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
            // Cambiar el insumo deja las fórmulas que su unidad usa (las otras las borra la base); "ninguna" no da fila, y no se guardan.
            ...(valor === "ninguna" ? undefined : actual),
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
      <p className="t-caption">Se completa con la pareja de lo que se elige en el otro material; el vendedor puede cambiarla.</p>
      <ul className="flex flex-col gap-2">
        {delQueElige.map((o) => {
          const actual = propias.find((p) => p.sigue_opcion_id === o.id);
          const valor = actual ? (actual.insumo_id ?? "ninguna") : "";
          return (
            <li key={o.id} className="flex flex-col gap-1">
              <span className="t-body-m">{insumos.get(o.insumo_id ?? "")?.nombre ?? "—"} →</span>
              <ParejaSelect insumos={insumos} valor={valor} onElegir={(v) => elegir(o, v)} />
              {actual?.insumo_id && (
                <button
                  type="button"
                  className="tap-target t-caption self-start text-left text-text-brand"
                  onClick={() => onAbrir(actual)}
                >
                  {detalleOpcion(actual) || "+ Fórmulas propias"}
                </button>
              )}
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
