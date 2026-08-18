const ZONA_AR = "America/Argentina/Buenos_Aires";

export function hoyISO(): string {
  return new Date().toLocaleDateString("en-CA", { timeZone: ZONA_AR });
}

export function sumarDiasISO(fechaISO: string, dias: number): string {
  const fecha = new Date(`${fechaISO}T00:00:00Z`);
  fecha.setUTCDate(fecha.getUTCDate() + dias);
  return fecha.toISOString().slice(0, 10);
}

export function diasEntreISO(desdeISO: string, hastaISO: string): number {
  const desde = new Date(`${desdeISO}T00:00:00Z`);
  const hasta = new Date(`${hastaISO}T00:00:00Z`);
  return Math.round((hasta.getTime() - desde.getTime()) / 86_400_000);
}
