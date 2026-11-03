import type { Contenido, InsumoBasico } from "../../types";

// Lo que una fórmula puede nombrar: variables, materiales (el único se llama como su insumo) y el peso y
// espesor de cada pieza. Que lo use seguro existe lo revisa el envío.
export function nombresDisponibles(c: Contenido, nombreInsumo: Map<string, InsumoBasico>): string[] {
  const materiales = c.materiales.map((m) =>
    m.tipo === "unico" ? nombreInsumo.get(m.insumo_id ?? "")?.nombre : m.nombre,
  );
  return [
    ...c.variables.map((v) => v.nombre),
    ...materiales.filter((n): n is string => Boolean(n)),
    ...c.piezas.map((p) => `peso ${p.nombre}`),
    ...c.piezas.filter((p) => p.calcula_espesor).map((p) => `espesor ${p.nombre}`),
  ];
}

export function Nombres({ nombres }: { nombres: string[] }) {
  if (nombres.length === 0) return null;
  return (
    <details className="t-caption">
      <summary className="tap-target cursor-pointer">Nombres que podés usar en una fórmula</summary>
      <p className="mt-1 font-mono">
        {[...new Set(nombres)].map((n) => (/[^\p{L}\p{N}_]/u.test(n) ? `[${n}]` : n)).join(" · ")}
      </p>
      <p className="mt-1">
        Operaciones: + − × / y paréntesis · comparar: &gt; &lt; &gt;= &lt;= = &lt;&gt; · y, o · si … entonces … si no …
        · redondear_arriba(…) · arcoseno(…) · pi. Coma decimal. Las medidas, en mm.
      </p>
    </details>
  );
}
