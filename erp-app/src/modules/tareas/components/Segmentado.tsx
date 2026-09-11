"use client";

// Una opción entre pocas, dentro de un formulario. Misma forma que el
// segmented de relación de la Lista y `FiltroDias`: el activo en brand-50,
// no en `btn-primary`, que en el sistema es un botón de acción.
export function Segmentado<V extends string>({
  opciones,
  valor,
  onChange,
  etiqueta,
}: {
  opciones: readonly { valor: V; label: string }[];
  valor: V;
  onChange: (valor: V) => void;
  etiqueta: string;
}) {
  return (
    <div className="inline-flex flex-wrap rounded-lg border border-border p-0.5" role="group" aria-label={etiqueta}>
      {opciones.map((o) => (
        <button
          key={o.valor}
          type="button"
          aria-pressed={o.valor === valor}
          onClick={() => onChange(o.valor)}
          className={`tap-target t-caption rounded-md px-3 py-1 ${
            o.valor === valor ? "bg-brand-50 font-semibold text-brand-700" : "text-text-tertiary"
          }`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
