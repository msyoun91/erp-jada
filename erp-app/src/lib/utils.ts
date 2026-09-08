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
  TA001: "Ese miembro tiene tareas activas en el proyecto — reasignalas antes de quitarlo",
  TA002: "Hay asignados que no son miembros del proyecto destino",
  TA003: "No tenés permiso para poner a otro usuario como responsable",
  TA004: "El paso previo todavía no está completado",
  TA005: "Esa cadena de pasos no es válida — el paso previo no se puede cambiar ni mezclar con recurrencia",
  TA006: "No se puede mover de hilo una tarea que es parte de una cadena de pasos",
  TA007: "Ese paso tiene un paso siguiente activo — desactivá la cadena desde el final",
  TA008: "No se pudo guardar: el registro ya no existe o no tenés permiso para modificarlo",
  TA009: "La plantilla no tiene pasos",
  email_exists: "Ese email ya está registrado",
  weak_password: "La contraseña es demasiado débil",
  invalid_credentials: "Email o contraseña incorrectos",
  email_not_confirmed: "Todavía no confirmaste tu email. Revisá tu casilla.",
  user_banned: "Tu cuenta está suspendida. Contactá a un administrador.",
  over_request_rate_limit: "Demasiados intentos. Esperá unos minutos e intentá de nuevo.",
};

// Clase `OB` (sql/032): el mensaje ya viene escrito para el usuario desde la
// base, y dos de ellos llevan un conteo que un texto fijo perdería. Lista
// blanca por código y no confianza en el mensaje: lo que no está marcado
// —incluido cualquier P0001 nuevo— sigue cayendo en el genérico.
const CODIGO_CON_MENSAJE_PROPIO = /^OB\d{3}$/;

export function mensajeError(error: unknown): string {
  const { code: codigo, message } = (error ?? {}) as { code?: string; message?: string };

  if (codigo && CODIGO_CON_MENSAJE_PROPIO.test(codigo) && message?.trim()) {
    return message;
  }

  return (codigo && MENSAJES_ERROR[codigo]) || "No se pudo completar la operación. Intentá de nuevo.";
}
