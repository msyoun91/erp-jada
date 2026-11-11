"use client";

import { useEffect, useState } from "react";
import { useForm, useWatch, type FieldError, type UseFormRegisterReturn } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { EntradaCampos } from "@/components/entrada/EntradaCampos";
import { Campo, claseInput } from "@/components/ui/Campo";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { aEntrada, desdeEntrada, ESTADO_VACIO, hayMalEscrita, type Entrada } from "@/lib/entrada";
import { MONEDAS } from "@/lib/monedas";
import { formatFecha } from "@/lib/utils";
import { formularioVenta, guardarRenglonCatalogo, guardarRenglonMano } from "../actions";
import type { VersionEditor } from "../queries";
import {
  aFormularioEntrada,
  formatAlicuota,
  pasarAPaquete,
  renglonCatalogoCampos,
  renglonManoSchema,
  type FormularioVenta,
  type RenglonCatalogoForm,
  type RenglonManoForm,
} from "../types";

type Renglon = VersionEditor["renglones"][number];
type Seccion = VersionEditor["secciones"][number];

export type Contexto = Pick<VersionEditor, "secciones" | "paquetes" | "formularios"> & { versionId: string };

// Sin `renglon`, uno nuevo en `seccionId`; con `duplicar`, uno nuevo con sus datos.
type Props = Contexto & {
  seccionId: string;
  renglon?: Renglon;
  // El que ve el cliente: el paquete con que se calculó, o la descripción.
  nombre?: string;
  duplicar?: boolean;
  onClose: () => void;
};

const CATALOGO_FORM = "presupuesto-renglon-catalogo";

// `formulario`: el del paquete del renglón, ya pedido al abrir; NULL si salió de la venta.
export function RenglonCatalogoPanel({
  versionId,
  secciones,
  paquetes,
  seccionId,
  renglon,
  nombre,
  duplicar,
  formulario: inicial,
  onClose,
}: Props & { formulario?: FormularioVenta | null }) {
  const editar = renglon && !duplicar ? renglon : undefined;
  const [formulario, setFormulario] = useState(inicial ?? null);
  const [estado, setEstado] = useState(() =>
    inicial && renglon?.entrada ? desdeEntrada(renglon.entrada, inicial) : ESTADO_VACIO,
  );
  const [opcionales, setOpcionales] = useState(renglon?.opcionales ?? []);
  // Editando, lo cargado viaja solo si se tocó (`renglonCatalogoSchema`).
  const [tocado, setTocado] = useState(false);
  const [cargando, setCargando] = useState(false);
  const [enviando, setEnviando] = useState(false);
  // Al agregar, el panel queda abierto para la ventana siguiente (decisiones/presupuestos.md → *Seguir cargando*).
  const [seguir, setSeguir] = useState(false);
  const [agregadas, setAgregadas] = useState(0);
  const { register, handleSubmit, formState, control, reset, getValues, setFocus } = useForm<RenglonCatalogoForm>({
    resolver: zodResolver(renglonCatalogoCampos),
    defaultValues: {
      id: editar?.id,
      version_id: versionId,
      seccion_id: seccionId,
      designacion: renglon?.designacion ?? "",
      ubicacion: renglon?.ubicacion ?? "",
      cantidad: renglon?.cantidad ?? 1,
      paquete_id: renglon?.paquete_id ?? "",
    },
  });
  const { errors } = formState;
  const paquete = useWatch({ control, name: "paquete_id" });
  const malEscrita = formulario !== null && hayMalEscrita(formulario, estado);
  const fueraDeVenta = renglon?.paquete_id && !paquetes.some((p) => p.paquete_id === renglon.paquete_id);

  // En un efecto: `reset` suelta las referencias de los campos, y el foco pedido en el mismo paso no llega.
  useEffect(() => {
    if (agregadas > 0) setFocus("designacion", { shouldSelect: true });
  }, [agregadas, setFocus]);

  async function elegirPaquete(id: string) {
    const antes: Entrada = formulario ? aEntrada(estado, formulario) : {};
    setTocado(true);
    setFormulario(null);
    if (!id) return;
    setCargando(true);
    const r = await formularioVenta(id);
    setCargando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    const f = r.formulario;
    setFormulario(f);
    if (!f) {
      setEstado(ESTADO_VACIO);
      return;
    }
    setEstado(pasarAPaquete(antes, f));
    setOpcionales((o) => o.filter((s) => f.servicios.some((x) => x.id === s)));
  }

  async function onSubmit(data: RenglonCatalogoForm) {
    const cargado =
      !editar || tocado
        ? { entrada: formulario ? aEntrada(estado, formulario) : (renglon?.entrada ?? {}), opcionales }
        : {};
    setEnviando(true);
    const result = await guardarRenglonCatalogo({ ...data, ...cargado });
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    // Con el panel abierto no se ve la fila: el aviso dice cuál entró.
    const etiqueta = [data.designacion, data.ubicacion].filter(Boolean).join(" · ");
    if (result.precio === null)
      toast.warning(`${etiqueta ? `${etiqueta} quedó` : "Quedó"} sin precio: ${result.mensaje ?? "revisá lo cargado"}`);
    else toast.success(editar ? "Renglón guardado" : etiqueta ? `Agregado: ${etiqueta}` : "Renglón agregado");
    if (editar || !seguir) {
      onClose();
      return;
    }
    // Lo que se escribe en mm no pasa a la siguiente: olvidado, queda sin precio y avisa; heredado, no avisa.
    const medidas = new Set(formulario?.variables.filter((v) => !v.es_lista && !v.es_cantidad).map((v) => v.id));
    setEstado((e) => ({
      ...e,
      variables: Object.fromEntries(Object.entries(e.variables).filter(([id]) => !medidas.has(id))),
    }));
    setTocado(false);
    reset({ ...getValues(), designacion: siguienteDesignacion(data.designacion ?? ""), ubicacion: "", cantidad: 1 });
    setAgregadas((n) => n + 1);
  }

  const tocar = <T,>(set: (v: T) => void) => (v: T) => {
    setTocado(true);
    set(v);
  };

  return (
    <RightPanel
      title={editar ? "Editar renglón" : "Renglón de Catálogo"}
      subtitle={editar ? nombre : undefined}
      onClose={onClose}
      hayCambios={formState.isDirty || tocado}
      footer={
        <PiePanel
          confirmar={editar ? "Guardar" : "Agregar"}
          enviando={enviando}
          onCancelar={onClose}
          form={CATALOGO_FORM}
          deshabilitado={cargando || malEscrita}
          nota={
            !editar ? (
              <label className="tap-target flex items-center gap-2">
                <input type="checkbox" checked={seguir} onChange={(e) => setSeguir(e.target.checked)} />
                <span className="t-body-m">Seguir cargando</span>
              </label>
            ) : editar.mantener && editar.condiciones_en ? (
              `Mantenida: se calcula con los precios del ${formatFecha(editar.condiciones_en)}.`
            ) : (
              "El precio lo calcula Catálogo al guardar, a hoy."
            )
          }
        />
      }
    >
      <form
        id={CATALOGO_FORM}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <CamposEtiqueta designacion={register("designacion")} ubicacion={register("ubicacion")} errores={errors} />
        {editar?.mantener ? (
          // Mantener recalcula con la versión del origen, que es de este paquete (PR013).
          <div>
            <p className="t-label mb-1">Paquete</p>
            <p className="t-body-m text-text-primary">{nombre}</p>
            <p className="t-caption mt-1">Mantenida: el paquete no se cambia. Para cambiarlo, antes pasala a hoy.</p>
          </div>
        ) : (
          <Campo id="renglon-paquete" label="Paquete" requerido error={errors.paquete_id}>
            <select
              id="renglon-paquete"
              aria-required
              className={claseInput(errors.paquete_id)}
              {...register("paquete_id", { onChange: (e) => elegirPaquete(e.target.value) })}
            >
              <option value="">Elegí el paquete</option>
              {fueraDeVenta && <option value={renglon?.paquete_id ?? ""}>{nombre} (ya no está a la venta)</option>}
              {[...Map.groupBy(paquetes, (p) => p.categoria)].map(([categoria, lista]) => (
                <optgroup key={categoria} label={categoria}>
                  {lista.map((p) => (
                    <option key={p.paquete_id} value={p.paquete_id}>
                      {p.nombre}
                    </option>
                  ))}
                </optgroup>
              ))}
            </select>
          </Campo>
        )}

        {cargando && <p className="t-caption">Cargando el paquete…</p>}
        {!cargando && formulario === null && paquete && (
          <p className="alert alert-warning">
            El paquete ya no está a la venta: se cambian la designación, la ubicación, la cantidad y la sección, o se elige
            otro.
          </p>
        )}
        {!cargando && formulario && (
          <>
            <EntradaCampos
              key={formulario.version_id}
              formulario={aFormularioEntrada(formulario)}
              estado={estado}
              onChange={tocar(setEstado)}
            />
            {formulario.servicios.length > 0 && (
              <fieldset className="flex flex-col">
                <legend className="t-label mb-1">Opcionales</legend>
                {formulario.servicios.map((s) => (
                  <label key={s.id} className="tap-target flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={opcionales.includes(s.id)}
                      onChange={(e) =>
                        tocar(setOpcionales)(
                          e.target.checked ? [...opcionales, s.id] : opcionales.filter((x) => x !== s.id),
                        )
                      }
                    />
                    <span className="t-body-m">{s.nombre}</span>
                  </label>
                ))}
              </fieldset>
            )}
          </>
        )}

        <Campo id="renglon-cantidad" label="Cantidad" requerido error={errors.cantidad}>
          <input
            id="renglon-cantidad"
            type="number"
            step="any"
            min="0"
            inputMode="decimal"
            aria-required
            className={claseInput(errors.cantidad)}
            {...register("cantidad")}
          />
        </Campo>
        <CampoSeccion seccion={register("seccion_id")} error={errors.seccion_id} secciones={secciones} />
      </form>
    </RightPanel>
  );
}

const MANO_FORM = "presupuesto-renglon-mano";

export function RenglonManoPanel({ versionId, secciones, seccionId, renglon, duplicar, onClose }: Props) {
  const [enviando, setEnviando] = useState(false);
  const editar = renglon && !duplicar ? renglon : undefined;
  // Un renglón a mano no cambia de moneda (PR009): editándolo, solo las secciones en la suya.
  const opciones = editar ? secciones.filter((s) => s.moneda === editar.moneda) : secciones;
  const { register, handleSubmit, formState, control } = useForm<RenglonManoForm>({
    resolver: zodResolver(renglonManoSchema),
    defaultValues: {
      id: editar?.id,
      version_id: versionId,
      seccion_id: seccionId,
      designacion: renglon?.designacion ?? "",
      ubicacion: renglon?.ubicacion ?? "",
      cantidad: renglon?.cantidad ?? 1,
      descripcion: renglon?.descripcion ?? "",
      precio: renglon?.precio === null || !renglon ? "" : String(renglon.precio).replace(".", ","),
    },
  });
  const { errors } = formState;
  const elegida = useWatch({ control, name: "seccion_id" });
  const seccion = secciones.find((s) => s.id === elegida);

  async function onSubmit(data: RenglonManoForm) {
    setEnviando(true);
    const result = await guardarRenglonMano(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(editar ? "Renglón guardado" : "Renglón agregado");
    onClose();
  }

  return (
    <RightPanel
      title={editar ? "Editar renglón a mano" : "Renglón a mano"}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <PiePanel
          confirmar={editar ? "Guardar" : "Agregar"}
          enviando={enviando}
          onCancelar={onClose}
          form={MANO_FORM}
          nota="Para lo que no está en Catálogo. Al publicar, le llega un aviso al jefe comercial."
        />
      }
    >
      <form
        id={MANO_FORM}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <Campo id="mano-descripcion" label="Descripción" requerido error={errors.descripcion}>
          <textarea
            id="mano-descripcion"
            aria-required
            rows={3}
            placeholder="Ej: Flete cerrado a Pilar"
            className={claseInput(errors.descripcion)}
            {...register("descripcion")}
          />
        </Campo>
        <Campo
          id="mano-precio"
          label={`Precio por unidad, sin IVA${seccion ? ` (${MONEDAS[seccion.moneda]})` : ""}`}
          requerido
          error={errors.precio}
        >
          <input
            id="mano-precio"
            type="text"
            inputMode="decimal"
            aria-required
            placeholder="Sin puntos: 150000 o 1500,5"
            className={claseInput(errors.precio)}
            {...register("precio")}
          />
        </Campo>
        <Campo id="mano-cantidad" label="Cantidad" requerido error={errors.cantidad}>
          <input
            id="mano-cantidad"
            type="number"
            step="any"
            min="0"
            inputMode="decimal"
            aria-required
            className={claseInput(errors.cantidad)}
            {...register("cantidad")}
          />
        </Campo>
        <CamposEtiqueta designacion={register("designacion")} ubicacion={register("ubicacion")} errores={errors} />
        <CampoSeccion seccion={register("seccion_id")} error={errors.seccion_id} secciones={opciones} />
        {editar && opciones.length < secciones.length && (
          <p className="t-caption -mt-2">
            Solo las secciones en {MONEDAS[editar.moneda]}: un renglón a mano no cambia de moneda.
          </p>
        )}
      </form>
    </RightPanel>
  );
}

// "V4 · Lavadero": lo que el cliente lee para ubicar el renglón.
function CamposEtiqueta({
  designacion,
  ubicacion,
  errores,
}: {
  designacion: UseFormRegisterReturn;
  ubicacion: UseFormRegisterReturn;
  errores: { designacion?: FieldError; ubicacion?: FieldError };
}) {
  return (
    <>
      <Campo id="renglon-designacion" label="Designación" error={errores.designacion}>
        <input id="renglon-designacion" placeholder="Ej: V4" className={claseInput(errores.designacion)} {...designacion} />
      </Campo>
      <Campo id="renglon-ubicacion" label="Ubicación" error={errores.ubicacion}>
        <input id="renglon-ubicacion" placeholder="Ej: Lavadero" className={claseInput(errores.ubicacion)} {...ubicacion} />
      </Campo>
    </>
  );
}

// "V4" → "V5", "PF-09" → "PF-10"; sin número al final, vacía.
function siguienteDesignacion(d: string) {
  const m = /^(.*?)(\d+)$/.exec(d);
  return m ? m[1] + String(Number(m[2]) + 1).padStart(m[2].length, "0") : "";
}

export function opcionSeccion(s: Seccion) {
  return `${s.nombre} · ${MONEDAS[s.moneda]} · IVA ${formatAlicuota(s.alicuota)}`;
}

function CampoSeccion({
  seccion,
  error,
  secciones,
}: {
  seccion: UseFormRegisterReturn;
  error?: FieldError;
  secciones: Seccion[];
}) {
  return (
    <Campo id="renglon-seccion" label="Sección" requerido error={error}>
      <select id="renglon-seccion" aria-required className={claseInput(error)} {...seccion}>
        {secciones.map((s) => (
          <option key={s.id} value={s.id}>
            {opcionSeccion(s)}
          </option>
        ))}
      </select>
    </Campo>
  );
}
