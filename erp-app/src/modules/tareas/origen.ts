// El deep link de una tarea generada por otro módulo. Solo rutas internas:
// `origen_punto` lo escribe quien inserta la fila y RLS no lo valida, así que
// un `javascript:` o un host ajeno llegarían intactos hasta el href. La misma
// regla vive en `crearTareaSchema` (escritura) — duplicada a propósito: es
// límite de seguridad, no lógica de negocio.
export function origenHref(punto: string | null): string | null {
  return punto && punto.startsWith("/") && !punto.startsWith("//") ? punto : null;
}
