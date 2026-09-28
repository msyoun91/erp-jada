type FieldError = { message?: string };

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
      <label htmlFor={id} className={`t-label mb-1 block ${requerido ? "t-label-req" : ""}`}>
        {label}
      </label>
      {children}
      {error && <p className="input-error-text">{error.message}</p>}
    </div>
  );
}

export function claseInput(error?: FieldError) {
  return `input ${error ? "input-error" : ""}`;
}
