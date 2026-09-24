import Link from "next/link";
import { REFERENCIA } from "../derivados";

// Se lee como el nombre que vio quien lo escribió: link ↗ si quien lee lo
// puede abrir (`enlaces`, de `getEnlaces`), texto plano si no.
export function TextoConReferencias({ texto, enlaces }: { texto: string; enlaces: Record<string, string> }) {
  const partes = texto.split(REFERENCIA);
  const salida = [];
  for (let i = 0; i < partes.length; i += 4) {
    salida.push(partes[i]);
    if (i + 3 >= partes.length) break;
    const [ente, id, nombre] = partes.slice(i + 1, i + 4);
    const href = enlaces[`${ente}:${id}`];
    salida.push(
      href ? (
        <Link key={i} href={href} className="font-semibold text-text-brand hover:underline">
          {nombre} ↗
        </Link>
      ) : (
        <span key={i} className="font-semibold text-text-primary">
          {nombre}
        </span>
      )
    );
  }
  return <p className="t-body-m whitespace-pre-wrap">{salida}</p>;
}
