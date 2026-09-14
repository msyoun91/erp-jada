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

// Cómo se nombra cada ente del catálogo `entes` (sql/055). La base sabe qué
// entes hay, qué datos ofrecen y qué permiso piden; no cómo se dicen. Un ente
// que no está acá no se ofrece en el editor de plantillas.
export const ENTES: Record<string, { un: string; el: string; estados: Record<string, string> }> = {
  obra: { un: "una obra", el: "la obra", estados: LABEL_ESTADO_OBRA },
};
