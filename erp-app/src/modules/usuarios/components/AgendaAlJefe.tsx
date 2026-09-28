export function AgendaAlJefe({
  equipo,
  checked,
  onChange,
}: {
  equipo: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="flex cursor-pointer items-start gap-3">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-0.5 h-4 w-4 shrink-0 accent-brand-700"
      />
      <span>
        <span className="t-body-m block text-text-primary">Su agenda pasa al jefe de {equipo}</span>
        <span className="t-caption block">
          {checked
            ? "El jefe la reparte con \"transferir\". Sus obras pasan al jefe igual."
            : "Se queda con sus contactos. Sus obras pasan al jefe igual."}
        </span>
      </span>
    </label>
  );
}
