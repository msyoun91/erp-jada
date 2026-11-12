// Copia de textoCargado (erp-app/src/modules/presupuestos/types.ts): las apps no se importan. Si cambia allá, cambia acá.
// shortcut: copiada a mano; si se comparte una segunda función, restaurar sync-contracts (GUIDE_SYNC.md).
export type Entrada = {
  variables?: Record<string, number | string>;
  color?: string | null;
  elecciones?: Record<string, Record<string, string | null>>;
};

// La copia no trae la versión de Catálogo del renglón: el orden de una medida se toma por nombre, de cualquier versión.
export function ordenPorNombre(orden: Record<string, number>): Map<string, number> {
  const m = new Map<string, number>();
  for (const [k, v] of Object.entries(orden)) {
    const nombre = k.slice(k.indexOf(":") + 1);
    if (!m.has(nombre)) m.set(nombre, v);
  }
  return m;
}

export function textoCargado(e: Entrada, nombres: Record<string, string>, orden: Map<string, number>): string | null {
  const ultimo = Number.MAX_SAFE_INTEGER;
  const partes = [
    ...Object.entries(e.variables ?? {})
      .sort(([a], [b]) => (orden.get(a) ?? ultimo) - (orden.get(b) ?? ultimo))
      .map(([n, v]) => `${n} ${String(v).replace(".", ",")}`),
    e.color && nombres[e.color],
    ...Object.values(e.elecciones ?? {}).flatMap((m) =>
      Object.entries(m).map(([material, insumo]) =>
        insumo === null ? `sin ${material}` : insumo in nombres && `${material}: ${nombres[insumo]}`,
      ),
    ),
  ];
  const texto = [...new Set(partes.filter((p): p is string => !!p))].join(" · ");
  return texto || null;
}
