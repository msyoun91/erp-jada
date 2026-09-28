import type { MotivoPerdida, OrigenObra, TipoObra } from "./types";

export const ORIGEN: Record<OrigenObra, string> = {
  referente: "Referente",
  cartel: "Cartel en obra",
  web_redes: "Web o redes",
  cliente_anterior: "Cliente anterior",
  llamado: "Llamado",
  otro: "Otro",
};

export const TIPO: Record<TipoObra, string> = {
  edificio_residencial: "Edificio residencial",
  casa: "Casa",
  oficinas_comercial: "Oficinas o comercial",
  industrial: "Industrial",
  otro: "Otro",
};

// El ejemplo guía el detalle libre (`decisiones/obras.md` → *El motivo de pérdida*).
export const MOTIVO: Record<MotivoPerdida, { label: string; ejemplo: string }> = {
  precio: { label: "Precio", ejemplo: "Estuvimos 10% más caros" },
  plazo: { label: "Plazo", ejemplo: "Necesitaban la entrega en marzo" },
  producto: { label: "Producto", ejemplo: "Pedían corredizas de PVC" },
  proveedor_habitual: { label: "Proveedor habitual", ejemplo: "Siguen con el de la obra anterior" },
  obra_suspendida: { label: "Obra suspendida", ejemplo: "Frenaron por financiamiento" },
  sin_respuesta: { label: "Sin respuesta", ejemplo: "Tres llamados sin contestar" },
  otro: { label: "Otro", ejemplo: "Contá qué pasó" },
};
