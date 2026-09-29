import Link from "next/link";
import { ACCION, REFERENCIA } from "../derivados";

// Se lee como el nombre que vio quien lo escribió: link ↗ si quien lee lo
// puede abrir (`enlaces`, de `getEnlaces`), texto plano si no. `{@accion|…}`
// va a `accion` (`hrefAccion`); sin él, texto plano. Una referencia con
// pestaña al lado (`pestanas`) la activa en vez de navegar.
export function TextoConReferencias({
  texto,
  enlaces,
  accion = null,
  pestanas = [],
  onPestana,
}: {
  texto: string;
  enlaces: Record<string, string>;
  accion?: string | null;
  pestanas?: string[];
  onPestana?: (ref: string) => void;
}) {
  const salida = [];
  const trozos = texto.split(ACCION);
  for (let j = 0; j < trozos.length; j++) {
    if (j % 2 === 1) {
      salida.push(
        accion ? (
          <Link key={`a${j}`} href={accion} className="font-semibold text-text-brand hover:underline">
            {trozos[j]} ↗
          </Link>
        ) : (
          <span key={`a${j}`} className="font-semibold text-text-primary">
            {trozos[j]}
          </span>
        )
      );
      continue;
    }
    const partes = trozos[j].split(REFERENCIA);
    for (let i = 0; i < partes.length; i += 4) {
      salida.push(partes[i]);
      if (i + 3 >= partes.length) break;
      const [ente, id, nombre] = partes.slice(i + 1, i + 4);
      const ref = `${ente}:${id}`;
      const href = enlaces[ref];
      salida.push(
        onPestana && pestanas.includes(ref) ? (
          <button key={`${j}-${i}`} type="button" onClick={() => onPestana(ref)} className="font-semibold text-text-brand hover:underline">
            {nombre} ↗
          </button>
        ) : href ? (
          <Link key={`${j}-${i}`} href={href} className="font-semibold text-text-brand hover:underline">
            {nombre} ↗
          </Link>
        ) : (
          <span key={`${j}-${i}`} className="font-semibold text-text-primary">
            {nombre}
          </span>
        )
      );
    }
  }
  return <p className="t-body-m whitespace-pre-wrap">{salida}</p>;
}
