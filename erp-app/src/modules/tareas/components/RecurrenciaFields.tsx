"use client";

import { useState } from "react";
import { aISO, desdeISO, formatFecha, hoyISO } from "@/lib/utils";
import type { RecurrenciaIntervalo } from "../types";

export type RecurrenciaValue = {
  recurrencia_activa: boolean;
  recurrencia_una_vez: boolean;
  recurrencia_intervalo: RecurrenciaIntervalo;
  recurrencia_cada: number;
  recurrencia_proxima: string;
};

function calcularProxima(intervalo: RecurrenciaIntervalo, cada: number): string {
  const d = desdeISO(hoyISO());
  if (intervalo === "dia") d.setDate(d.getDate() + cada);
  else if (intervalo === "mes") d.setMonth(d.getMonth() + cada);
  else d.setFullYear(d.getFullYear() + cada);
  return aISO(d);
}

export function RecurrenciaFields({
  value,
  onChange,
}: {
  value: RecurrenciaValue;
  onChange: (value: RecurrenciaValue) => void;
}) {
  const [fechaManual, setFechaManual] = useState(false);

  return (
    <div>
      <label className="flex items-center gap-2">
        <input
          type="checkbox"
          checked={value.recurrencia_activa}
          onChange={(e) => {
            const activa = e.target.checked;
            const proxima =
              activa && !value.recurrencia_proxima
                ? calcularProxima(value.recurrencia_intervalo, value.recurrencia_cada)
                : value.recurrencia_proxima;
            onChange({ ...value, recurrencia_activa: activa, recurrencia_proxima: proxima });
          }}
        />
        <span className="t-label">Repetir automáticamente</span>
      </label>

      {value.recurrencia_activa && (
        <div className="mt-3 flex flex-col gap-3">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={value.recurrencia_una_vez}
              onChange={(e) => {
                const unaVez = e.target.checked;
                const proxima =
                  unaVez && !value.recurrencia_proxima
                    ? calcularProxima(value.recurrencia_intervalo, value.recurrencia_cada)
                    : value.recurrencia_proxima;
                onChange({ ...value, recurrencia_una_vez: unaVez, recurrencia_proxima: proxima });
              }}
            />
            <span className="t-caption">Repetir una sola vez</span>
          </label>

          {value.recurrencia_una_vez ? (
            <div>
              <label className="t-label mb-1 block">Fecha</label>
              <input
                type="date"
                className="input"
                min={hoyISO()}
                value={value.recurrencia_proxima}
                onChange={(e) => onChange({ ...value, recurrencia_proxima: e.target.value })}
              />
            </div>
          ) : (
            <>
              <div className="flex items-center gap-2">
                <span className="t-body-m">Cada</span>
                <input
                  type="number"
                  min={1}
                  className="input w-20"
                  value={value.recurrencia_cada}
                  onChange={(e) => {
                    const cada = Math.max(1, Number(e.target.value));
                    const proxima = fechaManual ? value.recurrencia_proxima : calcularProxima(value.recurrencia_intervalo, cada);
                    onChange({ ...value, recurrencia_cada: cada, recurrencia_proxima: proxima });
                  }}
                />
                <select
                  className="input"
                  value={value.recurrencia_intervalo}
                  onChange={(e) => {
                    const intervalo = e.target.value as RecurrenciaIntervalo;
                    const proxima = fechaManual ? value.recurrencia_proxima : calcularProxima(intervalo, value.recurrencia_cada);
                    onChange({ ...value, recurrencia_intervalo: intervalo, recurrencia_proxima: proxima });
                  }}
                >
                  <option value="dia">día(s)</option>
                  <option value="mes">mes(es)</option>
                  <option value="anio">año(s)</option>
                </select>
              </div>

              <div>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={fechaManual}
                    onChange={(e) => {
                      const manual = e.target.checked;
                      setFechaManual(manual);
                      if (!manual) {
                        onChange({
                          ...value,
                          recurrencia_proxima: calcularProxima(value.recurrencia_intervalo, value.recurrencia_cada),
                        });
                      }
                    }}
                  />
                  <span className="t-caption">Elegir fecha de inicio manualmente</span>
                </label>

                {fechaManual ? (
                  <input
                    type="date"
                    className="input mt-2"
                    min={hoyISO()}
                    value={value.recurrencia_proxima}
                    onChange={(e) => onChange({ ...value, recurrencia_proxima: e.target.value })}
                  />
                ) : (
                  <p className="t-caption mt-1">Próxima repetición: {formatFecha(value.recurrencia_proxima)}</p>
                )}
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}
