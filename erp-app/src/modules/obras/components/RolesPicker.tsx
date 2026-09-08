"use client";

// Multi-select de roles: la relación es una sola fila con array de roles, no
// una fila por rol. Sirve igual para empresa y para persona.
export function RolesPicker<T extends string>({
  opciones,
  labels,
  seleccionados,
  onChange,
  error,
}: {
  opciones: readonly T[];
  labels: Record<T, string>;
  seleccionados: T[];
  onChange: (roles: T[]) => void;
  error?: string;
}) {
  function toggle(rol: T) {
    onChange(
      seleccionados.includes(rol)
        ? seleccionados.filter((r) => r !== rol)
        : [...seleccionados, rol],
    );
  }

  return (
    <div>
      <div className="flex flex-wrap gap-2" role="group" aria-label="Roles">
        {opciones.map((rol) => {
          const activo = seleccionados.includes(rol);
          return (
            <button
              key={rol}
              type="button"
              onClick={() => toggle(rol)}
              aria-pressed={activo}
              className={`tap-target t-caption rounded-lg border px-3 py-1 ${
                activo
                  ? "border-brand-500 bg-brand-50 font-semibold text-brand-700"
                  : "border-border text-text-tertiary"
              }`}
            >
              {labels[rol]}
            </button>
          );
        })}
      </div>
      {error && <p className="input-error-text mt-1">{error}</p>}
    </div>
  );
}
