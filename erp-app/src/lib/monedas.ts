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
