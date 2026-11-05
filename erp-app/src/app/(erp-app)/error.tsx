"use client";

export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <div className="empty-state">
      <p className="t-h3">No se pudo cargar esta sección</p>
      <p className="t-body-m mt-1 mb-4">Puede ser la conexión. Probá de nuevo en un momento.</p>
      <button className="btn btn-secondary" onClick={reset}>
        Reintentar
      </button>
    </div>
  );
}
