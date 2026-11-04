import type { Contenido, Entrada } from "./types";

// El formulario guarda por id; la entrada va por nombre (`db_schema/catalogo.md` → *La entrada*). Vacío es
// "sin valor": la base usa el predeterminado.
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

export function aEntrada(e: EntradaEstado, c: Contenido): Entrada {
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

export function desdeEntrada(entrada: Entrada, c: Contenido): EntradaEstado {
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
