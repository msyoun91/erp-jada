"use client";

import { useRef, useState, useTransition } from "react";
import { FileText, PackageOpen } from "lucide-react";
import { toast } from "sonner";
import { EntradaCampos } from "@/components/entrada/EntradaCampos";
import { Campo } from "@/components/ui/Campo";
import { Vacio } from "@/components/ui/Vacio";
import { aEntrada, ESTADO_VACIO, hayMalEscrita, type Entrada, type EntradaEstado } from "@/lib/entrada";
import { formatMonto, MONEDAS, MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import { calcularVentana, formularioVenta } from "../actions";
import {
  aFormularioEntrada,
  pasarAPaquete,
  textoCargado,
  type FormularioVenta,
  type PrecioCatalogo,
  type VentanaForm,
} from "../types";
import { AltaPresupuestoPanel, type NuevaObraSlot } from "./AltaPresupuestoPanel";

type Calculo = {
  ventana: VentanaForm;
  nombre: string;
  detalle: string | null;
  precio: PrecioCatalogo;
  minimos: { nombre: string; monto: number }[];
};

// "Ancho 1500 · Alto 1100 · Negro · con Colocación": lo que escribió el vendedor, para reconocer la ventana en el alta.
function detalle(entrada: Entrada, f: FormularioVenta, opcionales: string[]) {
  const nombres = new Map<string, string>([
    ...f.colores.flatMap((c) => (c.id && c.nombre ? [[c.id, c.nombre] as const] : [])),
    ...f.opciones.flatMap((o) => (o.insumo_id && o.nombre ? [[o.insumo_id, o.nombre] as const] : [])),
  ]);
  const orden = (variable: string) => {
    const i = f.variables.findIndex((v) => v.nombre === variable);
    return i < 0 ? undefined : i;
  };
  const partes = [
    textoCargado(entrada, nombres, orden),
    ...f.servicios.filter((s) => opcionales.includes(s.id)).map((s) => `con ${s.nombre}`),
  ];
  return partes.filter(Boolean).join(" · ") || null;
}

// La consulta rápida del vendedor: el precio de hoy de una ventana, sin guardar, y "Llevar a un presupuesto" con ella.
export function CalculadoraVenta({
  paquetes,
  obras,
  monedaPrincipal,
  NuevaObra,
}: {
  paquetes: { paquete_id: string; nombre: string; categoria: string }[];
  obras: { id: string; nombre: string }[];
  monedaPrincipal: Moneda;
  NuevaObra?: NuevaObraSlot;
}) {
  const [paquete, setPaquete] = useState("");
  const [formulario, setFormulario] = useState<FormularioVenta | null>(null);
  const [estado, setEstado] = useState<EntradaEstado>(ESTADO_VACIO);
  const [opcionales, setOpcionales] = useState<string[]>([]);
  const [moneda, setMoneda] = useState<Moneda>(monedaPrincipal);
  const [cargando, setCargando] = useState(false);
  const [calculo, setCalculo] = useState<Calculo | null>(null);
  const [pendiente, startTransition] = useTransition();
  const [llevando, setLlevando] = useState(false);
  // Cambiar algo borra el cálculo, y el que estaba en curso no se muestra: lo que se ve y se lleva es lo cargado.
  const vuelta = useRef(0);

  function cambiar<T>(set: (v: T) => void) {
    return (v: T) => {
      vuelta.current++;
      setCalculo(null);
      set(v);
    };
  }

  async function elegirPaquete(id: string) {
    const antes = formulario ? aEntrada(estado, formulario) : null;
    cambiar(setPaquete)(id);
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
    if (!f) {
      toast.error("Este paquete ya no está a la venta");
      return;
    }
    setFormulario(f);
    setEstado(antes ? pasarAPaquete(antes, f) : ESTADO_VACIO);
    setOpcionales((o) => o.filter((s) => f.servicios.some((x) => x.id === s)));
  }

  function calcular() {
    if (!formulario) return;
    const f = formulario;
    const ventana: VentanaForm = { paquete_id: paquete, entrada: aEntrada(estado, f), opcionales, moneda };
    const n = ++vuelta.current;
    startTransition(async () => {
      const r = await calcularVentana(ventana);
      if (n !== vuelta.current) return;
      if (!r.success) {
        toast.error(r.error);
        return;
      }
      setCalculo({
        ventana,
        nombre: paquetes.find((p) => p.paquete_id === ventana.paquete_id)?.nombre ?? "",
        detalle: detalle(ventana.entrada, f, ventana.opcionales),
        precio: r.precio,
        minimos: r.minimos,
      });
    });
  }

  if (paquetes.length === 0) {
    return (
      <Vacio icono={PackageOpen} titulo="Nada a la venta todavía">
        Cuando Catálogo publique un paquete, se calcula acá.
      </Vacio>
    );
  }

  const malEscrita = formulario !== null && hayMalEscrita(formulario, estado);
  const precio = calculo?.precio.precio ?? null;

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,360px)_1fr]">
      <form
        className="flex flex-col gap-4"
        onSubmit={(e) => {
          e.preventDefault();
          calcular();
        }}
      >
        <Campo id="calc-paquete" label="Paquete" requerido>
          <select id="calc-paquete" aria-required className="input" value={paquete} onChange={(e) => elegirPaquete(e.target.value)}>
            <option value="">Elegí el paquete</option>
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

        {cargando && <p className="t-caption">Cargando el paquete…</p>}
        {!cargando && formulario && (
          <>
            <EntradaCampos
              key={formulario.version_id}
              formulario={aFormularioEntrada(formulario)}
              estado={estado}
              onChange={cambiar(setEstado)}
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
                        cambiar(setOpcionales)(
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

        <Campo id="calc-moneda" label="Moneda">
          <select
            id="calc-moneda"
            className="input"
            value={moneda}
            onChange={(e) => cambiar(setMoneda)(e.target.value as Moneda)}
          >
            {MONEDAS_LISTA.map((m) => (
              <option key={m} value={m}>
                {MONEDAS[m]}
              </option>
            ))}
          </select>
        </Campo>

        <button type="submit" className="btn btn-primary" disabled={!formulario || cargando || pendiente || malEscrita}>
          {pendiente ? "Calculando…" : "Calcular"}
        </button>
      </form>

      <div className={pendiente ? "opacity-60" : ""}>
        {calculo ? (
          <Resultado calculo={calculo} onLlevar={() => setLlevando(true)} />
        ) : (
          <p className="t-body-m">Elegí el paquete, cargá las medidas y tocá Calcular.</p>
        )}
      </div>

      {llevando && calculo && precio !== null && (
        <AltaPresupuestoPanel
          obras={obras}
          ventana={{ ...calculo.ventana, nombre: calculo.nombre, detalle: calculo.detalle, precio }}
          NuevaObra={NuevaObra}
          onClose={() => setLlevando(false)}
        />
      )}
    </div>
  );
}

// Sin precio, solo por qué: no hay qué llevar. Los mínimos, como saldrían en un presupuesto con esta ventana sola.
function Resultado({ calculo, onLlevar }: { calculo: Calculo; onLlevar: () => void }) {
  const { precio, minimos, ventana } = calculo;
  const avisos = (precio.mensajes ?? []).map((m) => m.mensaje);

  if (precio.precio === null) {
    return (
      <div className="alert alert-warning">
        <p className="font-medium">Sin precio</p>
        {[...new Set([precio.mensaje, ...avisos])].filter(Boolean).map((m) => (
          <p key={m}>{m}</p>
        ))}
      </div>
    );
  }

  const total = precio.precio + minimos.reduce((s, m) => s + m.monto, 0);
  return (
    <div className="flex flex-col gap-4 rounded-lg border border-border bg-bg-surface p-4">
      <div>
        <p className="t-caption">{calculo.nombre}</p>
        <p className="t-h2">{formatMonto(precio.precio, ventana.moneda)}</p>
        <p className="t-caption">Sin IVA, a precios de hoy</p>
      </div>
      {avisos.length > 0 && (
        <div className="alert alert-warning">
          {avisos.map((m) => (
            <p key={m}>{m}</p>
          ))}
        </div>
      )}
      {minimos.length > 0 && (
        <div className="border-t border-border pt-3">
          <p className="t-label mb-1">Si es la única ventana</p>
          {minimos.map((m) => (
            <p key={m.nombre} className="t-body-m flex justify-between gap-3">
              <span>Mínimo de {m.nombre}</span>
              <span>+ {formatMonto(m.monto, ventana.moneda)}</span>
            </p>
          ))}
          <p className="t-body-m mt-1 flex justify-between gap-3 font-medium text-text-primary">
            <span>Total</span>
            <span>{formatMonto(total, ventana.moneda)}</span>
          </p>
        </div>
      )}
      <button type="button" className="btn btn-primary self-start" onClick={onLlevar}>
        <FileText size={16} />
        Llevar a un presupuesto
      </button>
    </div>
  );
}
