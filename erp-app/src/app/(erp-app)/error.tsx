"use client";

export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <div className="empty-state">
      <p className="t-body-m mb-4">No se pudo cargar esta sección.</p>
      <button className="btn btn-secondary" onClick={reset}>
        Reintentar
      </button>
    </div>
  );
}
