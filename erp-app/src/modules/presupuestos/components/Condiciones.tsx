import type { Bloque } from "../types";

// Las particulares de la versión y los bloques generales que van, numerados: lo mismo en el editor y en el impreso.
export function Condiciones({ particulares, generales = [] }: { particulares?: string | null; generales?: Bloque[] }) {
  return (
    <>
      {particulares && (
        <div className="print:break-inside-avoid">
          <p className="t-label mb-1">Condiciones particulares</p>
          <p className="t-body-m whitespace-pre-line">{particulares}</p>
        </div>
      )}
      {generales.length > 0 && (
        <div className="flex flex-col gap-2">
          <p className="t-label">Términos y condiciones</p>
          {generales.map((b, i) => (
            <div key={b.id} className="print:break-inside-avoid">
              <p className="t-body-m font-semibold text-text-primary">
                {i + 1}. {b.titulo}
              </p>
              <p className="t-body-m whitespace-pre-line">{b.texto}</p>
            </div>
          ))}
        </div>
      )}
    </>
  );
}
