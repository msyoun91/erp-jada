import { z } from "zod";
import { idSchema } from "@/lib/validacion";

// Lo que cargaría un vendedor (`db_schema/catalogo.md` → *La entrada*). La base revisa la forma (CA017).
export const entradaSchema = z.object({
  variables: z.record(z.string(), z.union([z.number(), z.string()])).optional(),
  elecciones: z.record(z.string(), z.record(z.string(), idSchema.nullable())).optional(),
  piezas: z.record(z.string(), z.boolean()).optional(),
  color: idSchema.optional(),
});
export type Entrada = z.infer<typeof entradaSchema>;

// Lo que el formulario lee del contenido de una versión. Lo cumplen el contenido de Catálogo y lo que da
// `catalogo_venta_formulario`, con las mismas claves.
export type PiezaEntrada = {
  id: string;
  nombre: string;
  opcional: boolean;
  incluida: boolean;
  requiere_pieza_id: string | null;
  secundario: boolean;
};
export type VariableEntrada = {
  id: string;
  nombre: string;
  pieza_id: string | null;
  ingresa_vendedor: boolean;
  es_lista: boolean;
  valores: string[];
  es_cantidad: boolean;
  minimo: number | null;
  maximo: number | null;
  secundario: boolean;
};
export type MaterialEntrada = {
  id: string;
  pieza_id: string;
  nombre: string | null;
  tipo: string;
  sin_eleccion: boolean;
  secundario: boolean;
};
export type ContenidoEntrada = { piezas: PiezaEntrada[]; variables: VariableEntrada[]; materiales: MaterialEntrada[] };

// Lo que además muestra el formulario: el predeterminado de cada variable en texto, el nombre de cada opción y los
// colores, con lo que no se ofrece en cada uno (vacío donde no se sabe, como en la calculadora de Catálogo).
export type FormularioEntrada = {
  piezas: PiezaEntrada[];
  variables: (VariableEntrada & { predeterminado: string | null })[];
  materiales: MaterialEntrada[];
  opciones: { id: string; material_id: string; insumo_id: string | null; predeterminada: boolean; nombre: string }[];
  colores: { id: string; nombre: string; base: boolean; piezas_fuera: string[]; opciones_fuera: string[] }[];
};

// El formulario guarda por id; la entrada va por nombre. Vacío es "sin valor": la base usa el predeterminado.
export type EntradaEstado = {
  variables: Record<string, string>;
  piezas: Record<string, "" | "si" | "no">;
  // "" la predeterminada o la pareja, "ninguna" sin elección, o el insumo.
  elecciones: Record<string, string>;
  color: string;
};

export const ESTADO_VACIO: EntradaEstado = { variables: {}, piezas: {}, elecciones: {}, color: "" };

// Como en una fórmula, el decimal es la coma y el punto no se acepta: `1.500` es mil quinientos, y `3.00`, metros
// de una planilla. Sin esto los dos entran como otro número. "1," pasa para no marcar error a mitad de escribir.
export function numeroEscrito(texto: string): number | null {
  const t = texto.trim();
  return /^-?\d+(,\d*)?$/.test(t) ? Number(t.replace(",", ".")) : null;
}

export function textoMedida(n: number): string {
  return n.toLocaleString("es-AR", { maximumFractionDigits: 2 });
}

export function malEscrita(v: VariableEntrada, e: EntradaEstado): boolean {
  const valor = e.variables[v.id]?.trim();
  return !v.es_lista && !!valor && numeroEscrito(valor) === null;
}

export function hayMalEscrita(c: ContenidoEntrada, e: EntradaEstado): boolean {
  return c.variables.some((v) => v.ingresa_vendedor && malEscrita(v, e));
}

export function aEntrada(e: EntradaEstado, c: ContenidoEntrada): Entrada {
  const entrada: Entrada = {};
  const pieza = new Map(c.piezas.map((p) => [p.id, p.nombre]));

  for (const v of c.variables) {
    const valor = e.variables[v.id]?.trim();
    if (!v.ingresa_vendedor || !valor) continue;
    const escrito = v.es_lista ? valor : numeroEscrito(valor);
    if (escrito === null) continue;
    entrada.variables ??= {};
    entrada.variables[v.nombre] = escrito;
  }
  for (const p of c.piezas) {
    const valor = e.piezas[p.id];
    if (!p.opcional || !valor) continue;
    entrada.piezas ??= {};
    entrada.piezas[p.nombre] = valor === "si";
  }
  for (const m of c.materiales) {
    const valor = e.elecciones[m.id];
    const nombrePieza = pieza.get(m.pieza_id);
    if ((m.tipo !== "elige_vendedor" && m.tipo !== "sigue") || !valor || !nombrePieza || !m.nombre) continue;
    entrada.elecciones ??= {};
    entrada.elecciones[nombrePieza] ??= {};
    entrada.elecciones[nombrePieza][m.nombre] = valor === "ninguna" ? null : valor;
  }
  if (e.color) entrada.color = e.color;
  return entrada;
}

export function desdeEntrada(entrada: Entrada, c: ContenidoEntrada): EntradaEstado {
  const estado: EntradaEstado = { variables: {}, piezas: {}, elecciones: {}, color: entrada.color ?? "" };
  const pieza = new Map(c.piezas.map((p) => [p.id, p.nombre]));

  for (const v of c.variables) {
    const valor = entrada.variables?.[v.nombre];
    if (valor !== undefined) estado.variables[v.id] = v.es_lista ? String(valor) : String(valor).replace(".", ",");
  }
  for (const p of c.piezas) {
    const valor = entrada.piezas?.[p.nombre];
    if (valor !== undefined) estado.piezas[p.id] = valor ? "si" : "no";
  }
  for (const m of c.materiales) {
    const nombrePieza = pieza.get(m.pieza_id);
    if (!nombrePieza || !m.nombre) continue;
    const valor = entrada.elecciones?.[nombrePieza]?.[m.nombre];
    if (valor !== undefined) estado.elecciones[m.id] = valor === null ? "ninguna" : valor;
  }
  return estado;
}
