// El par etiqueta/valor de las tres fichas. Estaba escrito nueve veces con la
// misma forma; la `dl` que lo contiene arranca en una columna porque en un
// panel de 390px dos columnas dejan ~150px y una dirección entra cortada.
export function Dato({ etiqueta, valor }: { etiqueta: string; valor: React.ReactNode }) {
  if (!valor) return null;
  return (
    <div>
      <dt className="t-caption">{etiqueta}</dt>
      <dd className="t-body-m break-words">{valor}</dd>
    </div>
  );
}

// Suelto bajo la grilla, con el mismo estilo que un valor, se leía como un dato
// al que se le perdió el nombre.
export function Observaciones({ texto }: { texto: string | null }) {
  if (!texto) return null;
  return (
    <div className="mt-4 border-t border-border pt-4">
      <p className="t-caption">Observaciones</p>
      <p className="t-body-m whitespace-pre-wrap break-words">{texto}</p>
    </div>
  );
}
