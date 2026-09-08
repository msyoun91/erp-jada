import { tienePermiso } from "@/lib/permissions";

export function puedeVerObras() {
  return tienePermiso("obras_ver");
}

export function puedeCrearObra() {
  return tienePermiso("obras_crear");
}

export function puedeEditarObra() {
  return tienePermiso("obras_editar");
}

export function puedeVincular() {
  return tienePermiso("obras_vincular");
}

// Gatea la comisión entera, no solo el botón de editarla: la fila de
// obras_obra_referente contiene el porcentaje, así que verla es verla.
export function puedeVerReferentes() {
  return tienePermiso("obras_referentes");
}

// Implica ver todas las obras, no solo las propias — no se puede reasignar lo
// que no se ve. La RLS lo refleja.
export function puedeTransferir() {
  return tienePermiso("obras_transferir");
}

export function puedeDesactivarObra() {
  return tienePermiso("obras_desactivar");
}

export function puedeVerEmpresas() {
  return tienePermiso("obras_empresas");
}

export function puedeCrearEmpresa() {
  return tienePermiso("obras_empresas_crear");
}

export function puedeEditarEmpresa() {
  return tienePermiso("obras_empresas_editar");
}

export function puedeVerPersonas() {
  return tienePermiso("obras_personas");
}

export function puedeCrearPersona() {
  return tienePermiso("obras_personas_crear");
}

export function puedeEditarPersona() {
  return tienePermiso("obras_personas_editar");
}

export function puedeVincularPersonaEmpresa() {
  return tienePermiso("obras_personas_empresas");
}

// Ve la agenda completa, no solo las personas de sus obras. Es el permiso que
// levanta el alcance por fila de obras_personas.
export function puedeVerTodasLasPersonas() {
  return tienePermiso("obras_personas_todas");
}

// Ver los dos logs. Aparte de `obras_personas_todas` a propósito: ese permiso
// es "ver la agenda completa", este es "ver quién la estuvo mirando".
export function puedeVerAuditoria() {
  return tienePermiso("obras_auditoria");
}

export function puedeVerPendientes() {
  return tienePermiso("obras_pendientes");
}

// Es el "administrador" de los pedidos del usuario: el sistema no tiene roles,
// así que autorizar altas y vínculos es un submódulo más.
export function puedeAprobar() {
  return tienePermiso("obras_aprobar");
}
