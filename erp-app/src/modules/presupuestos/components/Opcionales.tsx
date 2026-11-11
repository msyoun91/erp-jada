"use client";

import { useOptimistic, useState, useTransition } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { aEntrada, colorDe, conPieza, desdeEntrada, fueraDe, incluida, type Entrada } from "@/lib/entrada";
import { guardarOpcionales, guardarRenglonCatalogo } from "../actions";
import type { OpcionalVersion, VersionEditor } from "../queries";
import { aFormularioEntrada, opcionalesDe, opcionalesSchema, type FormularioVenta, type OpcionalesForm } from "../types";
import { opcionSeccion } from "./RenglonPanel";

type Renglon = VersionEditor["renglones"][number];

const OPCIONALES_FORM = "presupuesto-opcionales";

// Cómo se ve cada opcional en la versión (decisiones/presupuestos.md → *Secciones y opcionales*).
export function OpcionalesPanel({
  versionId,
  opcionales,
  secciones,
  onClose,
}: {
  versionId: string;
  opcionales: OpcionalVersion[];
  secciones: VersionEditor["secciones"];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<OpcionalesForm>({
    resolver: zodResolver(opcionalesSchema),
    defaultValues: {
      version_id: versionId,
      opcionales: opcionales.map((o) => ({
        fila: o.fila,
        pieza: o.pieza,
        porcentaje_id: o.porcentaje_id,
        inicial: o.como,
        como: o.como,
      })),
    },
  });

  async function onSubmit(data: OpcionalesForm) {
    setEnviando(true);
    const result = await guardarOpcionales(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Opcionales guardados");
    onClose();
  }

  return (
    <RightPanel
      title="Cómo se ven los opcionales"
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <PiePanel
          confirmar="Guardar"
          enviando={enviando}
          onCancelar={onClose}
          form={OPCIONALES_FORM}
          nota="Lo ve así el cliente. Cambiarlo recalcula las ventanas que lo tienen."
        />
      }
    >
      <form
        id={OPCIONALES_FORM}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <p className="t-caption">
          En el precio, suma sin mostrarse. Debajo, una línea bajo cada ventana que lo lleva. Aparte, un renglón con la suma
          de todas, en la sección que elijas: con su moneda y su IVA.
        </p>
        {opcionales.map((o, i) => (
          <label key={o.clave} className="flex flex-col gap-1">
            <span className="t-label">{o.nombre}</span>
            <select className="input" {...register(`opcionales.${i}.como`)}>
              <option value="precio">En el precio</option>
              <option value="debajo">Debajo de cada ventana</option>
              <optgroup label="Aparte, en la sección">
                {secciones.map((s) => (
                  <option key={s.id} value={s.id}>
                    {opcionSeccion(s)}
                  </option>
                ))}
              </optgroup>
            </select>
          </label>
        ))}
      </form>
    </RightPanel>
  );
}

// Debajo de la ventana, la línea de un opcional que va debajo es también la casilla para elegirlo; los demás, un botón
// (decisiones/presupuestos.md → *Debajo de cada ventana…*). Cada clic guarda y recalcula la ventana.
export function OpcionalesVentana({
  versionId,
  renglon: r,
  formulario,
  formas,
  montos,
}: {
  versionId: string;
  renglon: Renglon;
  formulario: FormularioVenta;
  // Clave → "debajo" o la sección del aparte; sin clave, en el precio.
  formas: Record<string, string>;
  // Clave → el monto que va debajo, como se muestra.
  montos: Record<string, string | null>;
}) {
  const [pendiente, startTransition] = useTransition();
  const [visto, ver] = useOptimistic(
    { entrada: r.entrada ?? {}, opcionales: r.opcionales },
    (_: { entrada: Entrada; opcionales: string[] }, nuevo: { entrada: Entrada; opcionales: string[] }) => nuevo,
  );
  const f = aFormularioEntrada(formulario);
  const estado = desdeEntrada(visto.entrada, f);
  const fuera = fueraDe(f, colorDe(f, estado)).piezas;
  const lista = opcionalesDe(formulario).map((o) => {
    const pieza = f.piezas.find((p) => p.id === o.id);
    return {
      ...o,
      elegido: pieza ? incluida(pieza, estado) : visto.opcionales.includes(o.id),
      fuera: fuera.has(o.id),
    };
  });
  if (lista.length === 0) return null;
  type Item = (typeof lista)[number];

  function elegir(o: Item) {
    let { entrada, opcionales } = visto;
    if (o.tipo === "pieza") {
      const cambio = conPieza(f, estado, o.id, o.elegido ? "no" : "si");
      if (cambio.aviso) toast.info(cambio.aviso);
      entrada = { ...entrada, piezas: { ...entrada.piezas, ...aEntrada(cambio.estado, f).piezas } };
    } else {
      opcionales = o.elegido ? opcionales.filter((x) => x !== o.id) : [...opcionales, o.id];
    }
    startTransition(async () => {
      ver({ entrada, opcionales });
      const result = await guardarRenglonCatalogo({
        id: r.id,
        version_id: versionId,
        seccion_id: r.seccion_id,
        designacion: r.designacion,
        ubicacion: r.ubicacion,
        cantidad: r.cantidad,
        paquete_id: r.paquete_id ?? "",
        entrada,
        opcionales,
      });
      if (!result.success) toast.error(result.error);
      else if (result.precio === null) toast.warning(`Quedó sin precio: ${result.mensaje ?? "revisá lo cargado"}`);
    });
  }

  const deshabilitado = (o: Item) => pendiente || (o.fuera && !o.elegido);
  const titulo = (o: Item) => (o.fuera ? "No se ofrece en este color" : undefined);
  const debajo = lista.filter((o) => formas[o.clave] === "debajo");
  const botones = lista.filter((o) => formas[o.clave] !== "debajo");

  return (
    <div role="group" aria-label="Opcionales" aria-busy={pendiente} className="flex flex-col pl-3">
      {debajo.map((o) => (
        <label key={o.clave} title={titulo(o)} className="t-caption tap-target flex items-center justify-between gap-3">
          <span className="flex items-center gap-2">
            <input type="checkbox" checked={o.elegido} disabled={deshabilitado(o)} onChange={() => elegir(o)} />
            {o.nombre}
          </span>
          {o.elegido && <span className="tabular-nums">{montos[o.clave]}</span>}
        </label>
      ))}
      {botones.length > 0 && (
        <div className="flex flex-wrap gap-2 pt-1">
          {botones.map((o) => (
            <button
              key={o.clave}
              type="button"
              title={titulo(o)}
              aria-pressed={o.elegido}
              disabled={deshabilitado(o)}
              className={`btn btn-sm ${o.elegido ? "btn-primary" : "btn-secondary"}`}
              onClick={() => elegir(o)}
            >
              {o.nombre}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
