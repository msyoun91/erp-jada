"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Pencil, Settings } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { Vacio } from "@/components/ui/Vacio";
import { MONEDAS, MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import { formatFecha } from "@/lib/utils";
import { configurar } from "../actions";
import type { Configuracion } from "../queries";
import { configuracionSchema, formatAlicuota, type ConfiguracionForm } from "../types";

function dias(n: number) {
  return n === 1 ? "1 día" : `${n} días`;
}

function referencias(monedas: Moneda[]) {
  return monedas.length ? monedas.map((m) => MONEDAS[m]).join(", ") : "Ninguna";
}

// Cambiar crea otra fila y desactiva la vigente: el historial son todas (decisiones/presupuestos.md → *Pantallas*).
export function ConfiguracionView({ configuraciones }: { configuraciones: Configuracion[] }) {
  const [abierto, setAbierto] = useState(false);
  const vigente = configuraciones.find((c) => c.activo);
  const panel = abierto && <ConfiguracionPanel vigente={vigente} onClose={() => setAbierto(false)} />;

  if (!vigente) {
    return (
      <>
        <Vacio
          icono={Settings}
          titulo="Sin configurar todavía"
          accion={
            <button type="button" className="btn btn-primary" onClick={() => setAbierto(true)}>
              Configurar
            </button>
          }
        >
          Hasta que cargues el tope de descuento y el plazo de vencimiento no se puede publicar ningún presupuesto, y todo
          descuento pide autorización.
        </Vacio>
        {panel}
      </>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="card" aria-label="Vigente">
        <div className="mb-2 flex flex-wrap items-center gap-2">
          <h2 className="t-h3 min-w-0 flex-1">Vigente</h2>
          <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto(true)}>
            <Pencil size={14} />
            Cambiar
          </button>
        </div>
        <div className="flex flex-col gap-1">
          <Linea texto="Descuento sin autorización" valor={`hasta ${formatAlicuota(vigente.tope_descuento)}`} />
          <Linea texto="Las versiones vencen a los" valor={dias(vigente.plazo_dias)} />
          <Linea texto="Referencias en el portal" valor={referencias(vigente.monedas_referencia)} />
        </div>
        <p className="t-caption mt-2">
          Desde el {formatFecha(vigente.created_at)} · {vigente.quien ?? "—"}
        </p>
      </section>

      {configuraciones.length > 1 && (
        <section className="card" aria-label="Historial">
          <h2 className="t-h3 mb-2">Historial · {configuraciones.length}</h2>
          <ul className="flex flex-col">
            {configuraciones.map((c) => (
              <li key={c.id} className="row flex flex-wrap items-baseline gap-x-3 border-b border-border last:border-b-0">
                <span className="t-body-m min-w-0 flex-1">
                  {formatFecha(c.created_at)} · {c.quien ?? "—"}
                </span>
                <span className="t-body-m text-text-primary">
                  {formatAlicuota(c.tope_descuento)} · {dias(c.plazo_dias)} · {referencias(c.monedas_referencia)}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}
      {panel}
    </div>
  );
}

function Linea({ texto, valor }: { texto: string; valor: string }) {
  return (
    <p className="t-body-m flex justify-between gap-3">
      <span>{texto}</span>
      <span className="font-medium text-text-primary">{valor}</span>
    </p>
  );
}

const FORM = "presupuestos-configuracion";

function ConfiguracionPanel({ vigente, onClose }: { vigente: Configuracion | undefined; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<ConfiguracionForm>({
    resolver: zodResolver(configuracionSchema),
    defaultValues: {
      tope_descuento: vigente ? String(vigente.tope_descuento) : "",
      plazo_dias: vigente ? String(vigente.plazo_dias) : "",
      monedas_referencia: vigente ? vigente.monedas_referencia : ["ARS", "USD_OFICIAL"],
    },
  });
  const { errors } = formState;

  async function onSubmit(data: ConfiguracionForm) {
    setEnviando(true);
    const result = await configurar(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Configuración guardada");
    onClose();
  }

  return (
    <RightPanel
      title={vigente ? "Cambiar la configuración" : "Configurar"}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<PiePanel confirmar="Guardar" enviando={enviando} onCancelar={onClose} form={FORM} />}
    >
      {/* Sin noValidate, `max` frenaba el envío con el globo del navegador y no se veía el mensaje del campo. */}
      <form id={FORM} noValidate onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="conf-tope" label="Descuento sin autorización (%)" requerido error={errors.tope_descuento}>
          <input
            id="conf-tope"
            type="number"
            step="any"
            min="0"
            max="100"
            inputMode="decimal"
            aria-required
            className={claseInput(errors.tope_descuento)}
            {...register("tope_descuento")}
          />
          <p className="t-caption mt-1">
            Por encima, el descuento de una versión pide autorización. Un pedido ya hecho sigue pendiente aunque quede
            dentro del tope nuevo.
          </p>
        </Campo>
        <Campo id="conf-plazo" label="Plazo de vencimiento (días)" requerido error={errors.plazo_dias}>
          <input
            id="conf-plazo"
            type="number"
            min="1"
            max="365"
            inputMode="numeric"
            aria-required
            className={claseInput(errors.plazo_dias)}
            {...register("plazo_dias")}
          />
          <p className="t-caption mt-1">
            Cuenta desde que se publica la versión. Lo ya publicado conserva su vencimiento.
          </p>
        </Campo>
        <fieldset className="flex flex-col gap-1">
          <legend className="t-label mb-1">Referencias en el portal</legend>
          <p className="t-caption mb-1">
            El cliente ve el total también en estas monedas, al cambio del día, solo como referencia. Vale para todos los
            links, también los ya enviados.
          </p>
          {MONEDAS_LISTA.map((m) => (
            <label key={m} className="tap-target flex items-center gap-2">
              <input type="checkbox" value={m} {...register("monedas_referencia")} />
              <span className="t-body-m">{MONEDAS[m]}</span>
            </label>
          ))}
        </fieldset>
      </form>
    </RightPanel>
  );
}
