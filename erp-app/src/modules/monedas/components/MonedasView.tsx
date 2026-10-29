"use client";

import { useState, useTransition } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { TriangleAlert } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { MONEDAS, MONEDAS_LISTA, formatPesos, type Moneda } from "@/lib/monedas";
import { formatFecha, formatFechaHora } from "@/lib/utils";
import { confirmarTipoCambio, corregirTipoCambio, elegirPrincipal } from "../actions";
import { CLASE_NIVEL, textoAviso, textoCambio } from "../etiquetas";
import { corregirSchema, type Aviso, type CorregirForm, type FilaHistorial, type TipoCambioHoy } from "../types";

type MonedaConHistorial = TipoCambioHoy & { historial: FilaHistorial[] };

export function MonedasView({
  monedas,
  avisos,
  principal,
  puedeCorregir,
  puedeElegirPrincipal,
}: {
  monedas: MonedaConHistorial[];
  avisos: Aviso[];
  principal: Moneda;
  puedeCorregir: boolean;
  puedeElegirPrincipal: boolean;
}) {
  const [corrigiendo, setCorrigiendo] = useState<MonedaConHistorial | null>(null);

  return (
    <div className="flex flex-col gap-6">
      {avisos.length > 0 && (
        <ul className="flex flex-col gap-1">
          {avisos.map((a) => (
            <li key={`${a.aviso}-${a.moneda ?? ""}`} className="t-body-m flex items-start gap-2 text-warning-text">
              <TriangleAlert size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
              {textoAviso(a)}
            </li>
          ))}
        </ul>
      )}

      <Principal principal={principal} puedeElegir={puedeElegirPrincipal} />

      <div className="grid gap-4 md:grid-cols-3">
        {monedas.map((m) => (
          <TarjetaMoneda
            key={m.moneda}
            moneda={m}
            puedeCorregir={puedeCorregir}
            onCorregir={() => setCorrigiendo(m)}
          />
        ))}
      </div>

      {corrigiendo && <CorregirModal moneda={corrigiendo} onClose={() => setCorrigiendo(null)} />}
    </div>
  );
}

function Principal({ principal, puedeElegir }: { principal: Moneda; puedeElegir: boolean }) {
  const [elegida, setElegida] = useState(principal);
  const [pendiente, startTransition] = useTransition();

  function guardar() {
    startTransition(async () => {
      const r = await elegirPrincipal({ moneda: elegida });
      if (!r.success) toast.error(r.error);
      else toast.success(`La moneda principal es ${MONEDAS[elegida]}`);
    });
  }

  return (
    <section className="flex flex-col gap-2">
      <h2 className="t-label">Moneda principal</h2>
      <p className="t-body-m">
        Viene elegida en un presupuesto nuevo y al cargar un monto, y los totales se muestran en ella, cada monto
        con el tipo de cambio de su fecha.
      </p>
      {puedeElegir ? (
        <div className="flex flex-wrap items-center gap-2">
          <select
            aria-label="Moneda principal"
            className={`${claseInput()} w-auto`}
            value={elegida}
            onChange={(e) => setElegida(e.target.value as Moneda)}
          >
            {MONEDAS_LISTA.map((m) => (
              <option key={m} value={m}>
                {MONEDAS[m]}
              </option>
            ))}
          </select>
          <button className="btn btn-primary btn-sm" disabled={pendiente || elegida === principal} onClick={guardar}>
            Guardar
          </button>
        </div>
      ) : (
        <p className="t-body-m font-semibold">{MONEDAS[principal]}</p>
      )}
    </section>
  );
}

function TarjetaMoneda({
  moneda,
  puedeCorregir,
  onCorregir,
}: {
  moneda: MonedaConHistorial;
  puedeCorregir: boolean;
  onCorregir: () => void;
}) {
  const [confirmando, setConfirmando] = useState<FilaHistorial | null>(null);
  const pendiente = moneda.historial.find((h) => h.activo && h.vigente_desde === null) ?? null;

  return (
    <section className="card flex flex-col gap-3">
      <div className="flex items-start justify-between gap-2">
        <div>
          <h2 className="t-label">{MONEDAS[moneda.moneda]}</h2>
          <p className="t-h2">{moneda.valor === null ? "—" : formatPesos(moneda.valor)}</p>
          <p className="t-caption">{moneda.fecha ? `Del ${formatFecha(moneda.fecha)}` : "Todavía sin valor"}</p>
        </div>
        {puedeCorregir && (
          <button className="btn btn-secondary btn-sm" onClick={onCorregir}>
            Corregir
          </button>
        )}
      </div>

      {pendiente && (
        <div className="rounded-md bg-warning-bg p-3 text-warning-text">
          <p className="t-body-m">
            MonedAPI trajo {formatPesos(pendiente.valor)}
            {pendiente.anterior !== null && ` (${textoCambio(pendiente.anterior, pendiente.valor)})`}. No rige hasta
            confirmarlo; mientras tanto se usa el vigente.
          </p>
          {puedeCorregir && (
            <div className="mt-2 flex gap-2">
              <button className="btn btn-secondary btn-sm" onClick={() => setConfirmando(pendiente)}>
                Confirmar
              </button>
              <button className="btn btn-secondary btn-sm" onClick={onCorregir}>
                Corregir
              </button>
            </div>
          )}
        </div>
      )}

      <div>
        <h3 className="t-label mb-1">Historial</h3>
        {moneda.historial.length === 0 ? (
          <p className="t-caption">Sin valores todavía: se traen de MonedAPI al abrir cualquier pantalla.</p>
        ) : (
          <ul className="flex flex-col">
            {moneda.historial.map((h) => (
              <FilaHistorialItem key={h.id} fila={h} />
            ))}
          </ul>
        )}
      </div>

      {confirmando && (
        <ConfirmModal
          title={`Confirmar ${MONEDAS[moneda.moneda]}`}
          mensaje={`${formatPesos(confirmando.valor)} pasa a regir desde ahora para todo el ERP${
            confirmando.anterior !== null ? `, contra ${formatPesos(confirmando.anterior)} de antes` : ""
          }.`}
          confirmLabel="Confirmar"
          onClose={() => setConfirmando(null)}
          onConfirm={async () => {
            const r = await confirmarTipoCambio(confirmando.id);
            if (!r.success) toast.error(r.error);
            else toast.success("Confirmado");
          }}
        />
      )}
    </section>
  );
}

function FilaHistorialItem({ fila }: { fila: FilaHistorial }) {
  const descartado = !fila.activo;
  const quien =
    fila.origen === "manual"
      ? `A mano · ${fila.cargado_por ?? "—"}`
      : fila.confirmado_por
        ? `MonedAPI · confirmó ${fila.confirmado_por}`
        : "MonedAPI";

  return (
    <li className={`border-b border-border py-2 last:border-b-0 ${descartado ? "opacity-60" : ""}`}>
      <div className="flex items-baseline justify-between gap-2">
        <span className="t-body-m font-semibold">{formatPesos(fila.valor)}</span>
        {fila.anterior !== null && (
          <span className={fila.nivel ? CLASE_NIVEL[fila.nivel] : "t-caption"}>
            {textoCambio(fila.anterior, fila.valor)}
          </span>
        )}
      </div>
      <p className="t-caption">
        {quien} · del {formatFecha(fila.fecha)}
        {fila.vigente_desde
          ? ` · rige desde ${formatFechaHora(fila.vigente_desde)}`
          : descartado
            ? " · descartado"
            : " · espera confirmación"}
      </p>
    </li>
  );
}

function CorregirModal({ moneda, onClose }: { moneda: MonedaConHistorial; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const [rojo, setRojo] = useState<CorregirForm | null>(null);
  const { register, handleSubmit, formState } = useForm<CorregirForm>({
    resolver: zodResolver(corregirSchema),
    defaultValues: { moneda: moneda.moneda as CorregirForm["moneda"], valor: undefined, confirmar_rojo: false },
  });
  const { errors } = formState;

  async function enviar(data: CorregirForm) {
    setEnviando(true);
    const r = await corregirTipoCambio(data);
    setEnviando(false);
    if ("pideConfirmar" in r) {
      setRojo(data);
      return;
    }
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(`${MONEDAS[moneda.moneda]} corregido`);
    onClose();
  }

  return (
    <>
      <FormModal
        title={`Corregir ${MONEDAS[moneda.moneda]}`}
        confirmLabel="Guardar"
        onClose={onClose}
        onSubmit={handleSubmit(enviar)}
        enviando={enviando}
        hayCambios={formState.isDirty}
      >
        <p className="t-body-m">
          {moneda.valor === null ? "Todavía no hay valor." : `Hoy rige ${formatPesos(moneda.valor)}.`} El nuevo rige
          desde que lo guardás, y a los demás que pueden corregir les llega un aviso.
        </p>
        <Campo id="tipo-cambio-valor" label="Pesos por unidad" requerido error={errors.valor}>
          <input
            id="tipo-cambio-valor"
            type="number"
            inputMode="decimal"
            step="0.01"
            min="0"
            aria-required
            className={claseInput(errors.valor)}
            {...register("valor", { valueAsNumber: true })}
          />
        </Campo>
      </FormModal>
      {rojo && moneda.valor !== null && (
        <ConfirmModal
          title="Cambia 50 % o más"
          mensaje={`${formatPesos(moneda.valor)} → ${formatPesos(rojo.valor)} (${textoCambio(moneda.valor, rojo.valor)}). Todo lo que se convierte con ${MONEDAS[moneda.moneda]} cambia en esa proporción. ¿Está bien?`}
          confirmLabel="Sí, guardar"
          onClose={() => setRojo(null)}
          onConfirm={async () => {
            const r = await corregirTipoCambio({ ...rojo, confirmar_rojo: true });
            if (!r.success) {
              toast.error(r.error);
              return;
            }
            toast.success(`${MONEDAS[moneda.moneda]} corregido`);
            onClose();
          }}
        />
      )}
    </>
  );
}
