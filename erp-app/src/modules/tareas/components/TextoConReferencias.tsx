// `{ente:uuid|nombre}` (sql/119) se lee como el nombre que vio quien lo
// escribió. Sin `|nombre` no es referencia y queda tal cual.
const REFERENCIA = /\{[a-z_]+:[0-9a-f-]{36}\|([^}]*)\}/g;

export function TextoConReferencias({ texto }: { texto: string }) {
  const partes = texto.split(REFERENCIA);
  return (
    <p className="t-body-m whitespace-pre-wrap">
      {partes.map((p, i) =>
        i % 2 === 1 ? (
          <span key={i} className="font-semibold text-text-primary">
            {p}
          </span>
        ) : (
          p
        )
      )}
    </p>
  );
}
