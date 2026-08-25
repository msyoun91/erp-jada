"use client";

// Los roles son un array de enum: una empresa puede ser desarrolladora y
// constructora de la misma obra, y una persona arquitecta y decisora. El
// selector es el mismo para las dos, cambia la lista.
export function RolesPicker<T extends string>({
  opciones,
  labels,
  value,
  onChange,
  error,
}: {
  opciones: readonly T[];
  labels: Record<T, string>;
  value: T[];
  onChange: (roles: T[]) => void;
  error?: string;
}) {
  function alternar(rol: T) {
    onChange(value.includes(rol) ? value.filter((r) => r !== rol) : [...value, rol]);
  }

  return (
    <div>
      <label className="t-label t-label-req mb-1 block">Roles en esta obra</label>
      <div className="grid grid-cols-2 gap-x-3 rounded-md border-[1.5px] border-border-strong p-2">
        {opciones.map((rol) => (
          <label
            key={rol}
            className="tap-target flex cursor-pointer items-center gap-2 rounded-sm px-1 py-1.5 hover:bg-bg-subtle"
          >
            <input
              type="checkbox"
              checked={value.includes(rol)}
              onChange={() => alternar(rol)}
              className="h-4 w-4 shrink-0 accent-brand-700"
            />
            <span className="t-body-m truncate">{labels[rol]}</span>
          </label>
        ))}
      </div>
      {error && <p className="input-error-text">{error}</p>}
    </div>
  );
}
