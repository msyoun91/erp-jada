export function Dato({ label, valor }: { label: string; valor: React.ReactNode }) {
  return (
    <div>
      <p className="t-label">{label}</p>
      <p className="t-body-m text-text-primary">{valor || "—"}</p>
    </div>
  );
}
