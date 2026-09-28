import type { Database } from "@/lib/supabase/database.types";

type Enums = Database["public"]["Enums"];

// La base sabe qué entes hay (`entes`); esto, cómo se dicen. Los módulos
// re-exportan de acá, nunca tienen un segundo mapa (GUIDE_ENTES §2.2).
type Ente<Estado extends string = never, Rol extends string = never> = {
  nombre: string;
  un: string;
  el: string;
  estados: Record<Estado, { label: string; badge: string }>;
  roles: Record<Rol, string>;
  datos: Record<string, { label: string; ejemplo: string }>;
};

export type RolObra =
  | "cliente"
  | "decisor"
  | "desarrolladora"
  | "constructora"
  | "comercializadora"
  | "arquitecto"
  | "director_obra"
  | "referente";

const obra: Ente<Enums["estado_obra"], RolObra> = {
  nombre: "Obra",
  un: "una obra",
  el: "la obra",
  estados: {
    idea: { label: "Idea", badge: "badge-neutral" },
    en_busqueda: { label: "En búsqueda", badge: "badge-info" },
    en_cotizacion: { label: "En cotización", badge: "badge-brand" },
    contratada: { label: "Contratada", badge: "badge-success" },
    perdida: { label: "Perdida", badge: "badge-error" },
  },
  roles: {
    cliente: "Cliente",
    decisor: "Decisor",
    desarrolladora: "Desarrolladora",
    constructora: "Constructora",
    comercializadora: "Comercializadora",
    arquitecto: "Arquitecto",
    director_obra: "Director de obra",
    referente: "Referente",
  },
  datos: {
    nombre: { label: "Nombre", ejemplo: "Torre Belgrano" },
    direccion: { label: "Dirección", ejemplo: "Av. Cabildo 1234" },
    localidad: { label: "Localidad", ejemplo: "CABA" },
  },
};

const persona: Ente = {
  nombre: "Persona",
  un: "una persona",
  el: "la persona",
  estados: {},
  roles: {},
  datos: { nombre: { label: "Nombre", ejemplo: "Marta Gómez" } },
};

const empresa: Ente = {
  nombre: "Empresa",
  un: "una empresa",
  el: "la empresa",
  estados: {},
  roles: {},
  datos: { nombre: { label: "Nombre", ejemplo: "Constructora Sur" } },
};

export const ENTES = { obra, persona, empresa };

export type CodigoEnte = keyof typeof ENTES;

// Un vínculo de Contactos trae el ente como texto: el que no está acá se muestra crudo.
export function labelRol(ente: string, rol: string) {
  const roles: Record<string, string> | undefined = ENTES[ente as CodigoEnte]?.roles;
  return roles?.[rol] ?? rol;
}
