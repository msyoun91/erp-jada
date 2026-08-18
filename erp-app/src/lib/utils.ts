const ZONA_AR = "America/Argentina/Buenos_Aires";

export function hoyISO(): string {
  return new Date().toLocaleDateString("en-CA", { timeZone: ZONA_AR });
}

export function sumarDiasISO(fechaISO: string, dias: number): string {
  const fecha = new Date(`${fechaISO}T00:00:00Z`);
  fecha.setUTCDate(fecha.getUTCDate() + dias);
  return fecha.toISOString().slice(0, 10);
}

// Un `date` de Postgres ("2026-08-20") es la fecha que el usuario eligió: no se
// convierte de zona. Un `timestamptz` sí — se muestra en hora AR.
export function formatFecha(fecha: string): string {
  const d = fecha.length <= 10 ? new Date(`${fecha}T12:00:00Z`) : new Date(fecha);
  return d.toLocaleDateString("es-AR", { timeZone: ZONA_AR, day: "numeric", month: "numeric", year: "2-digit" });
}

export function formatFechaHora(iso: string): string {
  return new Date(iso).toLocaleString("es-AR", {
    timeZone: ZONA_AR,
    day: "numeric",
    month: "numeric",
    year: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function diasEntreISO(desdeISO: string, hastaISO: string): number {
  const desde = new Date(`${desdeISO}T00:00:00Z`);
  const hasta = new Date(`${hastaISO}T00:00:00Z`);
  return Math.round((hasta.getTime() - desde.getTime()) / 86_400_000);
}

// Errores de Supabase nunca se muestran crudos (son técnicos y en inglés).
// Mapa por código; lo no mapeado cae en un genérico.
const MENSAJES_ERROR: Record<string, string> = {
  "23505": "Ya existe un registro con esos datos",
  "23503": "El registro relacionado no existe",
  "23514": "Los datos no cumplen una regla del sistema",
  "42501": "No tenés permiso para hacer esto",
  email_exists: "Ese email ya está registrado",
  weak_password: "La contraseña es demasiado débil",
};

export function mensajeError(error: unknown): string {
  const codigo = (error as { code?: string } | null)?.code;
  return (codigo && MENSAJES_ERROR[codigo]) || "No se pudo completar la operación. Intentá de nuevo.";
}
