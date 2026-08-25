import type {
  EmpresaConRoles,
  EstadoObra,
  EstadoProspecto,
  Moneda,
  Persona,
  PersonaConRoles,
  RolEmpresa,
  RolPersona,
  TipoObra,
} from "../types";

// Etiquetas compartidas por listado y ficha: la misma obra no puede leerse
// distinto según dónde se la mire.

export const TIPO_OBRA_LABEL: Record<TipoObra, string> = {
  edificio_residencial: "Edificio residencial",
  edificio_comercial: "Edificio comercial",
  vivienda: "Vivienda",
  oficinas: "Oficinas",
  local: "Local",
  desarrollo_mixto: "Desarrollo mixto",
  otro: "Otro",
};

export const ESTADO_OBRA_LABEL: Record<EstadoObra, string> = {
  idea: "Idea",
  proyecto: "Proyecto",
  pozo: "Pozo",
  inicio_obra: "Inicio de obra",
  construccion: "Construcción",
  terminaciones: "Terminaciones",
  finalizada: "Finalizada",
  desconocido: "Desconocido",
};

export const ESTADO_PROSPECTO_LABEL: Record<EstadoProspecto, string> = {
  nuevo: "Nuevo",
  investigando: "Investigando",
  contactado: "Contactado",
  en_seguimiento: "En seguimiento",
  interes_confirmado: "Interés confirmado",
  cotizacion_solicitada: "Cotización solicitada",
  cotizado: "Cotizado",
  negociacion: "Negociación",
  ganado: "Ganado",
  perdido: "Perdido",
  sin_oportunidad: "Sin oportunidad",
};

// El estado del prospecto es clasificación, no un semáforo de gestión: solo se
// tiñen los tres desenlaces, el resto es neutro.
export const ESTADO_PROSPECTO_BADGE: Record<EstadoProspecto, string> = {
  nuevo: "badge-info",
  investigando: "badge-neutral",
  contactado: "badge-neutral",
  en_seguimiento: "badge-neutral",
  interes_confirmado: "badge-neutral",
  cotizacion_solicitada: "badge-neutral",
  cotizado: "badge-neutral",
  negociacion: "badge-warning",
  ganado: "badge-success",
  perdido: "badge-error",
  sin_oportunidad: "badge-neutral",
};

export const ROL_EMPRESA_LABEL: Record<RolEmpresa, string> = {
  desarrolladora: "Desarrolladora",
  constructora: "Constructora",
  inmobiliaria: "Inmobiliaria",
  estudio_arquitectura: "Estudio de arquitectura",
  inversor: "Inversor",
  proveedor: "Proveedor",
  otro: "Otro",
};

export const ROL_PERSONA_LABEL: Record<RolPersona, string> = {
  arquitecto: "Arquitecto",
  desarrollador: "Desarrollador",
  inversor: "Inversor",
  director: "Director",
  compras: "Compras",
  oficina_tecnica: "Oficina técnica",
  decisor: "Decisor",
  influenciador: "Influenciador",
  contacto_comercial: "Contacto comercial",
  otro: "Otro",
};

export function nombrePersona(persona: Pick<Persona, "nombre" | "apellido"> | null) {
  if (!persona) return "—";
  return [persona.nombre, persona.apellido].filter(Boolean).join(" ");
}

export function nombreEmpresa(
  empresa: { razon_social: string; nombre_comercial?: string | null } | null
) {
  if (!empresa) return "—";
  return empresa.nombre_comercial || empresa.razon_social;
}

// "Empresa principal" del listado no es una columna: se deriva por prioridad de
// rol. Una columna propia se desincronizaría con obra_empresa.
const PRIORIDAD_ROL: RolEmpresa[] = [
  "desarrolladora",
  "constructora",
  "inmobiliaria",
  "estudio_arquitectura",
  "inversor",
  "proveedor",
  "otro",
];

export function empresaPrincipal(relaciones: EmpresaConRoles[]): EmpresaConRoles | null {
  const activas = relaciones.filter((r) => r.activo);
  if (activas.length === 0) return null;

  return activas.reduce((mejor, actual) => {
    const rango = (r: EmpresaConRoles) =>
      Math.min(...r.roles.map((rol) => PRIORIDAD_ROL.indexOf(rol)));
    return rango(actual) < rango(mejor) ? actual : mejor;
  });
}

export function referente(relaciones: PersonaConRoles[]): PersonaConRoles | null {
  return relaciones.find((r) => r.activo && r.es_referente) ?? null;
}

export function formatMonto(monto: number | null, moneda: Moneda | null) {
  if (monto === null || moneda === null) return "—";
  return `${moneda} ${monto.toLocaleString("es-AR", { maximumFractionDigits: 0 })}`;
}

export function formatPorcentaje(porcentaje: number) {
  return `${porcentaje.toLocaleString("es-AR", { maximumFractionDigits: 2 })}%`;
}

// Normaliza para comparar nombres al buscar duplicados: sin acentos, sin
// mayúsculas y sin espacios de más. No se guarda así, solo se compara.
export function normalizar(texto: string) {
  return texto
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/\s+/g, " ");
}
