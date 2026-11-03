// Los tres niveles de un cambio: el color lo decide la base (`nivel_cambio`), acá solo se pinta.
export type Nivel = "amarillo" | "naranja" | "rojo";

export const CLASE_NIVEL: Record<Nivel, string> = {
  amarillo: "badge badge-warning",
  naranja: "badge badge-error",
  rojo: "badge bg-error text-white",
};

export function textoCambio(anterior: number, valor: number): string {
  const pct = ((valor - anterior) / anterior) * 100;
  return `${pct > 0 ? "+" : ""}${pct.toLocaleString("es-AR", { maximumFractionDigits: 1 })} %`;
}
