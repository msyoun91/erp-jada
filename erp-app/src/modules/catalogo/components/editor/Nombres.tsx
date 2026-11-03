import type { RefObject } from "react";
import type { Contenido, InsumoBasico } from "../../types";

const RESERVADAS = new Set(["si", "entonces", "no", "y", "o", "pi"]);
const PALABRAS_REGLA = ["si", ">", "<", "=", "y", "o", "entonces", "si no"];

// Lo que una fórmula puede nombrar: variables, materiales (el único se llama como su insumo) y el peso y
// espesor de cada pieza. Que lo use seguro existe lo revisa el envío; una lista de valores nunca se puede usar.
export function nombresDisponibles(c: Contenido, nombreInsumo: Map<string, InsumoBasico>): string[] {
  const materiales = c.materiales.map((m) =>
    m.tipo === "unico" ? nombreInsumo.get(m.insumo_id ?? "")?.nombre : m.nombre,
  );
  return [
    ...c.variables.filter((v) => !v.es_lista).map((v) => v.nombre),
    ...materiales.filter((n): n is string => Boolean(n)),
    ...c.piezas.map((p) => `peso ${p.nombre}`),
    ...c.piezas.filter((p) => p.calcula_espesor).map((p) => `espesor ${p.nombre}`),
  ];
}

// Una sola palabra que no sea reservada va suelta; todo lo demás, entre corchetes.
export function comoFormula(nombre: string) {
  const suelto = /^[\p{L}_][\p{L}\p{N}_]*$/u.test(nombre) && !RESERVADAS.has(nombre.toLowerCase());
  return suelto ? nombre : `[${nombre}]`;
}

export function Nombres({ nombres }: { nombres: string[] }) {
  if (nombres.length === 0) return null;
  return (
    <details className="t-caption">
      <summary className="tap-target cursor-pointer">Nombres que podés usar en una fórmula</summary>
      <p className="mt-1 font-mono">{[...new Set(nombres)].map(comoFormula).join(" · ")}</p>
      <p className="mt-1">
        Operaciones: + − × / y paréntesis · comparar: &gt; &lt; &gt;= &lt;= = &lt;&gt; · y, o · si … entonces … si no …
        · redondear_arriba(…) · arcoseno(…) · pi. Coma decimal. Las medidas, en mm.
      </p>
    </details>
  );
}

// Botones que escriben en la regla, donde quedó el cursor: los nombres no se memorizan ni se escriben mal.
export function ArmarRegla({
  textarea,
  onCambio,
  opciones,
  nombres,
}: {
  textarea: RefObject<HTMLTextAreaElement | null>;
  onCambio: (valor: string) => void;
  opciones: string[];
  nombres: string[];
}) {
  function escribir(texto: string) {
    const el = textarea.current;
    if (!el) return;
    const { selectionStart: inicio, selectionEnd: fin, value } = el;
    const antes = value.slice(0, inicio);
    const despues = value.slice(fin);
    const pieza = `${antes && !/\s$/.test(antes) ? " " : ""}${texto}${/^\s/.test(despues) ? "" : " "}`;
    onCambio(antes + pieza + despues);
    el.focus();
    el.setSelectionRange(inicio + pieza.length, inicio + pieza.length);
  }

  const grupo = (titulo: string, textos: string[], aviso?: string) => (
    <div role="group" aria-label={titulo}>
      <p className="t-caption mb-1">{titulo}</p>
      {aviso && <p className="t-caption mb-1 text-warning-text">{aviso}</p>}
      <div className="flex flex-wrap gap-1">
        {textos.map((t) => (
          <button
            key={t}
            type="button"
            className="btn btn-secondary btn-sm tap-target max-w-full whitespace-normal break-words font-mono"
            onClick={() => escribir(t)}
          >
            {t}
          </button>
        ))}
      </div>
    </div>
  );

  return (
    <div className="mt-2 flex flex-col gap-2">
      {grupo("Armar", PALABRAS_REGLA)}
      {grupo(
        "Termina en",
        [...opciones.map(comoFormula), "ninguno"],
        opciones.length > 0 ? undefined : "Sumá las opciones para verlas acá.",
      )}
      {nombres.length > 0 && grupo("Comparar", [...new Set(nombres)].map(comoFormula))}
    </div>
  );
}
