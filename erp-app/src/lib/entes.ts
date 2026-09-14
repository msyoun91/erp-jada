import type { Enums } from "@/lib/supabase/database.types";

// Los enums viajan en snake_case a la base; la UI nunca los muestra crudos.
// Vive acá y no en obras porque Tareas también lo muestra (disparadores).
export const LABEL_ESTADO_OBRA: Record<Enums<"estado_obra">, string> = {
  idea: "Idea",
  en_cotizacion: "En cotización",
  en_ejecucion: "En ejecución",
  en_postventa: "En post-venta",
  perdida: "Perdida",
  terminada: "Terminada",
};

// Suben de obras por lo mismo que los estados: el editor de plantillas los
// ofrece para adjuntar y como condición (sql/060).
export const LABEL_ROL_EMPRESA: Record<Enums<"rol_empresa">, string> = {
  constructora: "Constructora",
  desarrolladora: "Desarrolladora",
  inmobiliaria: "Inmobiliaria",
  estudio_arquitectura: "Estudio de arquitectura",
  direccion_obra: "Dirección de obra",
  otro: "Otro",
};

export const LABEL_ROL_PERSONA: Record<Enums<"rol_persona">, string> = {
  arquitecto: "Arquitecto",
  desarrollador: "Desarrollador",
  inversor: "Inversor",
  director_obra: "Director de obra",
  compras: "Compras",
  oficina_tecnica: "Oficina técnica",
  decisor: "Decisor",
  influenciador: "Influenciador",
  contacto_comercial: "Contacto comercial",
  otro: "Otro",
};

// Cómo se nombra cada ente del catálogo `entes` (sql/055). La base sabe qué
// entes hay, qué datos ofrecen y qué permiso piden; no cómo se dicen. Solo el
// que tiene `estados` se ofrece como disparador en el editor de plantillas;
// los demás se relacionan con tareas (sql/059). Un dato sin entrada en `datos`
// no tiene chip. `ejemplo` es el de la vista previa. `roles`: por ente
// relacionado, los roles que una plantilla puede adjuntar o pedir (sql/060).
export const ENTES: Record<
  string,
  {
    nombre: string;
    un: string;
    el: string;
    estados?: Record<string, string>;
    roles?: Record<string, Record<string, string>>;
    datos: Record<string, { label: string; ejemplo: string }>;
  }
> = {
  obra: {
    nombre: "Obra",
    un: "una obra",
    el: "la obra",
    estados: LABEL_ESTADO_OBRA,
    roles: { empresa: LABEL_ROL_EMPRESA, persona: LABEL_ROL_PERSONA },
    datos: { nombre: { label: "Nombre de la obra", ejemplo: "Edificio Cabildo" } },
  },
  empresa: { nombre: "Empresa", un: "una empresa", el: "la empresa", datos: {} },
  persona: { nombre: "Persona", un: "una persona", el: "la persona", datos: {} },
};
