const TZ = "America/Argentina/Buenos_Aires";
const DIA_MS = 24 * 60 * 60 * 1000;

// El día calendario de un instante, en Argentina — no el del reloj del servidor
// (UTC en Vercel) ni el del navegador. Cliente y servidor tienen que coincidir o
// lo pospuesto reaparece un día antes.
export function diaISO(fecha: Date): string {
  return fecha.toLocaleDateString("en-CA", { timeZone: TZ });
}

export function hoyISO(): string {
  return diaISO(new Date());
}

export function desdeISO(iso: string): Date {
  return new Date(iso + "T00:00:00");
}

export function aISO(fecha: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${fecha.getFullYear()}-${pad(fecha.getMonth() + 1)}-${pad(fecha.getDate())}`;
}

export function sumarDias(iso: string, dias: number): string {
  const d = desdeISO(iso);
  d.setDate(d.getDate() + dias);
  return aISO(d);
}

export function diasEntre(desde: string, hasta: string): number {
  return Math.round((desdeISO(hasta).getTime() - desdeISO(desde).getTime()) / DIA_MS);
}

export function formatFecha(iso: string | null): string {
  if (!iso) return "";
  return desdeISO(iso).toLocaleDateString("es-AR");
}
