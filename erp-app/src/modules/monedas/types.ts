import { z } from "zod";
import type { Database } from "@/lib/supabase/database.types";
import { MONEDAS_LISTA } from "@/lib/monedas";

type Funciones = Database["public"]["Functions"];

// El generador declara no-nulas las columnas de un `RETURNS TABLE` (ver
// `notificaciones/types.ts`): estas llegan en null. Sin ningún valor guardado
// todavía, `monedas_hoy` trae la moneda con valor, fecha y última consulta en null.
export type TipoCambioHoy = {
  moneda: Funciones["monedas_hoy"]["Returns"][number]["moneda"];
  valor: number | null;
  fecha: string | null;
  ultima_consulta: string | null;
};

export type Aviso = {
  aviso: "monedapi_falla" | "por_confirmar" | "sin_actualizar";
  moneda: TipoCambioHoy["moneda"] | null;
  valor: number | null;
  desde: string;
};

export type FilaHistorial = Omit<
  Funciones["monedas_historial"]["Returns"][number],
  "anterior" | "nivel" | "cargado_por" | "confirmado_por" | "vigente_desde"
> & {
  anterior: number | null;
  nivel: "amarillo" | "naranja" | "rojo" | null;
  cargado_por: string | null;
  confirmado_por: string | null;
  vigente_desde: string | null;
};

const monedaConCambio = z.enum(["USD_OFICIAL", "USD_BLUE", "EUR"]);

export const corregirSchema = z.object({
  moneda: monedaConCambio,
  valor: z.number("Ingresá un número").positive("Tiene que ser mayor que cero"),
  confirmar_rojo: z.boolean().default(false),
});
export type CorregirForm = z.input<typeof corregirSchema>;

export const principalSchema = z.object({ moneda: z.enum(MONEDAS_LISTA) });
export type PrincipalForm = z.input<typeof principalSchema>;

// Lo que devuelve MonedAPI (`/api/v2/usd/oficial`): solo se usan el de venta y su fecha.
export const respuestaMonedapiSchema = z.object({
  sell: z.number().positive(),
  updatedAt: z.iso.datetime({ offset: true }),
});
