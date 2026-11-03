import { Ayuda } from "./Ayuda";

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
  ejemplo,
  children,
}: {
  id: string;
  label: string;
  requerido?: boolean;
  error?: FieldError;
  // Con ejemplo, la etiqueta lleva un "?" que lo muestra.
  ejemplo?: React.ReactNode;
  children: React.ReactNode;
}) {
  const clase = `t-label ${requerido ? "t-label-req" : ""}`;
  return (
    <div>
      {ejemplo ? (
        <Ayuda de={label} ejemplo={ejemplo} className="mb-1">
          <label htmlFor={id} className={clase}>
            <Etiqueta texto={label} />
          </label>
        </Ayuda>
      ) : (
        <label htmlFor={id} className={`${clase} mb-1 block`}>
          <Etiqueta texto={label} />
        </label>
      )}
      {children}
      {error && <p className="input-error-text">{error.message}</p>}
    </div>
  );
}

export function claseInput(error?: FieldError) {
  return `input ${error ? "input-error" : ""}`;
}
