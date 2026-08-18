export default function Loading() {
  return (
    <div className="flex items-center justify-center py-20">
      <span className="h-8 w-8 animate-spin rounded-full border-[3px] border-border border-t-brand-500" />
      <span className="sr-only">Cargando…</span>
    </div>
  );
}
