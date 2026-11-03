type FieldError = { message?: string };

// `.t-label` va en mayúsculas, y "ANCHO (MM)" se lee como megámetros: lo que está entre paréntesis (unidades,
// aclaraciones) queda como está escrito.
export function Etiqueta({ texto }: { texto: string }) {
  return texto.split(/(\([^)]*\))/).map((parte, i) =>
    i % 2 === 1 ? (
      <span key={i} className="normal-case">
        {parte}
      </span>
    ) : (
      parte
    ),
  );
}

export function Campo({
  id,
  label,
  requerido,
  error,
  children,
}: {
  id: string;
  label: string;
  requerido?: boolean;
  error?: FieldError;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label htmlFor={id} className={`t-label ${requerido ? "t-label-req" : ""} mb-1 block`}>
        <Etiqueta texto={label} />
      </label>
      {children}
      {error && <p className="input-error-text">{error.message}</p>}
    </div>
  );
}

export function claseInput(error?: FieldError) {
  return `input ${error ? "input-error" : ""}`;
}
