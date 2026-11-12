import type { Entrada } from "./cargado";

// La forma de lo que copia el ERP (db_schema/presupuestos.md → presupuestos_portal_copia). Lo descifrado llega como unknown
// hasta que se lo trata como Copia: lo escribe solo el ERP.
export type Linea = { clave: string; nombre: string; importe: number | null; importe_con_iva: number | null };
export type Aparte = Linea & { seccion_id: string };
export type Combinacion = {
  n: number;
  casillas: string[];
  publicada: boolean;
  importe: number | null;
  importe_con_iva: number | null;
  debajo: Linea[];
  aparte: Aparte[];
};
export type Renglon = {
  id: string;
  seccion_id: string;
  tipo: string;
  designacion: string | null;
  ubicacion: string | null;
  cantidad: number;
  nombre: string | null;
  minimo_de: string | null;
  entrada: Entrada | null;
  casillas: { clave: string; nombre: string }[];
  ancho: number;
  combinaciones: Combinacion[];
};
export type Seccion = { id: string; nombre: string; moneda: string; alicuota: number };
export type Version = {
  numero: number;
  variante: string;
  variante_nombre: string | null;
  iva_discriminado: boolean;
  descuento: number;
  vence: string | null;
  // Las copias anteriores a sql/205 no las traen.
  condiciones?: string | null;
  terminos?: string | null;
  secciones: Seccion[];
  aparte: { clave: string; seccion_id: string; piso: number | null }[];
  renglones: Renglon[];
  nombres: Record<string, string>;
  orden: Record<string, number>;
};
export type Copia = {
  revision: number;
  estado: "publicado" | "aprobado" | "cortado" | "no_disponible";
  codigo: string;
  nombre: string;
  aprobado_en: string | null;
  whatsapp: string | null;
  versiones: Version[];
};
export type Moneda = { moneda: string; valor: number; fecha: string; referencia: boolean };
