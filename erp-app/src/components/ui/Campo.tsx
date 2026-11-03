import { Ayuda } from "./Ayuda";

type FieldError = { message?: string };

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
            {label}
          </label>
        </Ayuda>
      ) : (
        <label htmlFor={id} className={`${clase} mb-1 block`}>
          {label}
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
