import { Constants, type Database } from "@/lib/supabase/database.types";

export type Moneda = Database["public"]["Enums"]["moneda"];

// En el orden del enum: ARS, USD oficial, USD blue, EUR.
export const MONEDAS_LISTA = Constants.public.Enums.moneda;

export const MONEDAS: Record<Moneda, string> = {
  ARS: "ARS",
  USD_OFICIAL: "USD oficial",
  USD_BLUE: "USD blue",
  EUR: "EUR",
};

export function formatPesos(valor: number) {
  return `$${valor.toLocaleString("es-AR", { maximumFractionDigits: 2 })}`;
}

// Lo que lee el cliente (impreso, editor de Presupuestos y portal): "US$ 7.180,00", "$ 1.240.000". El portal tiene la misma
// regla en erp-cliente (Presupuesto.tsx); "oficial" es una palabra interna y no va.
const SIMBOLO: Record<Moneda, string> = { ARS: "$", USD_OFICIAL: "US$", USD_BLUE: "US$ blue", EUR: "€" };

export function simboloCliente(moneda: Moneda) {
  return SIMBOLO[moneda];
}

export function formatMontoCliente(valor: number, moneda: Moneda) {
  const decimales = moneda === "ARS" ? 0 : 2;
  return `${SIMBOLO[moneda]} ${valor.toLocaleString("es-AR", { minimumFractionDigits: decimales, maximumFractionDigits: decimales })}`;
}

export function formatMonto(valor: number, moneda: Moneda) {
  return moneda === "ARS"
    ? formatPesos(valor)
    : `${MONEDAS[moneda]} ${valor.toLocaleString("es-AR", { maximumFractionDigits: 2 })}`;
}
